// Keeping a real Chrome profile safe while Qi (CEF) runs it.
//
// - Chrome holds <user data dir>/SingletonLock (a symlink "host-pid") while
//   it runs. Two browsers on one profile corrupt it, so Qi refuses to
//   open a dir whose lock belongs to a live process and says who holds it.
//   A stale lock (the pid is gone, e.g. after a reboot) is taken over the
//   way Chrome itself does.
// - Before the first run of the day with a given CEF version, the whole user
//   data dir (minus caches) is copied to
//   ~/.local/share/qi/chrome-backups/<browser>-<date>-cef<version>/.
//   The newest three of that browser are kept. A backup is not marked done
//   if a browser took the lock while the copy was running.
// - Chrome session files are moved aside for the run, onto the profile's own
//   disk, and put back on exit, so Qi does not open Chromium's windows and
//   does not replace them.
#include <fcntl.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <sstream>
#include <vector>

#include "include/cef_parser.h"
#include "include/cef_version.h"
#include "qi.h"

namespace fs = std::filesystem;

namespace qi {
namespace {

std::string ReadAll(const std::string& path) {
  std::ifstream f(path);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

std::string Canon(const std::string& path) {
  std::error_code ec;
  fs::path c = fs::weakly_canonical(fs::path(path), ec);
  return (!ec && !c.empty()) ? c.string() : path;
}

bool Inside(const std::string& outer, const std::string& inner) {
  std::string a = Canon(outer);
  std::string b = Canon(inner);
  if (a == b) return true;
  if (!a.empty() && a.back() != '/') a.push_back('/');
  return b.rfind(a, 0) == 0;
}

std::string FnvHex(const std::string& s) {
  uint64_t h = 14695981039346656037ull;
  for (unsigned char c : s) {
    h ^= c;
    h *= 1099511628211ull;
  }
  char buf[17];
  snprintf(buf, sizeof(buf), "%016llx", static_cast<unsigned long long>(h));
  return buf;
}

const char* kSessionNames[] = {
    "Sessions", "Current Session", "Current Tabs", "Last Session", "Last Tabs",
};

// Inside the profile directory, so the rename stays on that filesystem.
// StateDir() can be a different mount from a custom --user-data-dir.
std::string HoldDir(const std::string& profile_dir) {
  return profile_dir + "/.qi-session-hold";
}

bool SkipDot(const std::string& name) { return name.empty() || name[0] == '.'; }

std::string ProfileRootOf(const std::string& file) {
  auto slash = file.find_last_of('/');
  if (slash == std::string::npos || slash == 0) return "";
  auto slash2 = file.find_last_of('/', slash - 1);
  if (slash2 == std::string::npos) return "";
  return file.substr(0, slash2);
}

// A live browser on this machine has the profile. A stale lock, or one that
// names another computer, does not.
bool ProfileRootBusy(const std::string& file) {
  std::string root = ProfileRootOf(file);
  if (root.empty()) return false;
  std::string holder = LiveLockHolder(root);
  if (holder.empty() || holder.find("another computer") != std::string::npos) return false;
  return true;
}

bool Escapes(const fs::path& rel) {
  if (rel.empty() || rel.is_absolute()) return true;
  for (const auto& part : rel)
    if (part == "..") return true;
  return false;
}

fs::path LexicalRel(const fs::path& path, const fs::path& base) {
  return path.lexically_normal().lexically_relative(base.lexically_normal());
}

struct StartupPref {
  std::string folder;
  std::string path;
  bool had = false;
  int value = 0;
};

std::vector<StartupPref>& StartupPrefs() {
  static std::vector<StartupPref> v;
  return v;
}

std::string& HeldRoot() {
  static std::string root;
  return root;
}

std::string HoldNote(const std::string& suffix) {
  return StateDir() + "/session-hold/" + std::to_string(static_cast<long long>(getpid())) +
         suffix;
}

std::string ManifestPath() { return HoldNote(".manifest"); }

std::string PrefSidecarPath() { return HoldNote(".prefs"); }

// One line per moved file: "<profile path>\t<hold path>". The wrapper reads
// this if the process dies before ReleaseBrowserSessions runs.
bool NoteHeld(const std::string& dest, const std::string& src) {
  std::string line = dest + '\t' + src + '\n';
  int fd = open(ManifestPath().c_str(), O_CREAT | O_WRONLY | O_APPEND | O_CLOEXEC, 0600);
  if (fd < 0) return false;
  const char* p = line.data();
  size_t left = line.size();
  bool ok = true;
  while (left) {
    ssize_t n = ::write(fd, p, left);
    if (n < 0) {
      if (errno == EINTR) continue;
      ok = false;
      break;
    }
    p += n;
    left -= static_cast<size_t>(n);
  }
  if (ok && ::fsync(fd) != 0) ok = false;
  if (::close(fd) != 0) ok = false;
  return ok;
}

bool RestorePair(const std::string& dest, const std::string& src) {
  if (!Exists(src)) return true;
  if (ProfileRootBusy(dest)) return false;
  std::error_code ec;
  fs::remove_all(dest, ec);
  fs::rename(src, dest, ec);
  if (ec) {
    std::cerr << "qi-cef: couldn't put back " << dest << ": " << ec.message() << "\n";
    return false;
  }
  return true;
}

void KeepLines(const std::string& path, const std::vector<std::string>& lines) {
  std::error_code ec;
  if (lines.empty()) {
    fs::remove(path, ec);
    return;
  }
  const std::string tmp = path + ".tmp";
  {
    std::ofstream o(tmp, std::ios::trunc);
    for (auto& line : lines) o << line << '\n';
    o.flush();
    if (!o) {
      fs::remove(tmp, ec);
      return;
    }
  }
  fs::rename(tmp, path, ec);
  if (ec) fs::remove(tmp, ec);
}

void RestoreManifest(const std::string& path) {
  std::ifstream in(path);
  std::string line;
  std::vector<std::string> left;
  while (std::getline(in, line)) {
    auto tab = line.find('\t');
    if (tab == std::string::npos) continue;
    if (!RestorePair(line.substr(0, tab), line.substr(tab + 1))) left.push_back(line);
  }
  in.close();
  KeepLines(path, left);
}

// A previous Qi that died left its manifest behind. Put those files back
// before this process holds anything. Leave a manifest whose process is
// still running alone.
void RecoverDeadManifests() {
  std::error_code ec;
  const fs::path dir = StateDir() + "/session-hold";
  if (!fs::is_directory(dir, ec)) return;
  std::vector<std::string> dead;
  for (auto& e : fs::directory_iterator(dir, ec)) {
    std::string name = e.path().filename().string();
    const std::string suffix = ".manifest";
    if (name.size() <= suffix.size() ||
        name.compare(name.size() - suffix.size(), suffix.size(), suffix) != 0)
      continue;
    std::string digits = name.substr(0, name.size() - suffix.size());
    bool numeric = !digits.empty();
    for (char c : digits)
      numeric = numeric && std::isdigit(static_cast<unsigned char>(c));
    if (!numeric) continue;
    long pid = std::atol(digits.c_str());
    if (pid == getpid()) continue;
    if (pid > 0 && kill(static_cast<pid_t>(pid), 0) == 0) continue;
    if (pid > 0 && errno != ESRCH) continue;
    dead.push_back(e.path().string());
  }
  for (auto& path : dead) RestoreManifest(path);
}

bool ReleaseOne(const std::string& profile) {
  const std::string hold = HoldDir(profile);
  if (!Exists(hold)) return true;
  bool ok = true;
  for (const char* name : kSessionNames) {
    const fs::path src = fs::path(hold) / name;
    if (!Exists(src.string())) continue;
    const fs::path dst = fs::path(profile) / name;
    std::error_code ec;
    fs::remove_all(dst, ec);
    fs::rename(src, dst, ec);
    if (ec) {
      std::cerr << "qi-cef: couldn't put back " << dst.string() << ": " << ec.message()
                << "\n";
      ok = false;
    }
  }
  if (ok) {
    std::error_code ec;
    fs::remove_all(hold, ec);
  }
  return ok;
}

}  // namespace

std::string LiveLockHolder(const std::string& dir) {
  char buf[512];
  ssize_t n = readlink((dir + "/SingletonLock").c_str(), buf, sizeof(buf) - 1);
  if (n <= 0) return "";
  std::string target(buf, n);
  auto dash = target.rfind('-');
  if (dash == std::string::npos) return "";
  std::string host = target.substr(0, dash);
  int pid = atoi(target.c_str() + dash + 1);
  char me[256] = {0};
  gethostname(me, sizeof(me) - 1);
  if (host != me) return target + " (another computer)";
  if (pid <= 0 || pid == getpid()) return "";
  if (kill(pid, 0) != 0 && errno == ESRCH) return "";  // stale
  std::ifstream comm("/proc/" + std::to_string(pid) + "/comm");
  std::string name;
  std::getline(comm, name);
  return name.empty() ? "pid " + std::to_string(pid)
                      : name + " (pid " + std::to_string(pid) + ")";
}

bool LockHeldByQi(const std::string& dir) {
  char buf[512];
  ssize_t n = readlink((dir + "/SingletonLock").c_str(), buf, sizeof(buf) - 1);
  if (n <= 0) return false;
  std::string target(buf, n);
  auto dash = target.rfind('-');
  if (dash == std::string::npos) return false;
  char me[256] = {0};
  gethostname(me, sizeof(me) - 1);
  if (target.substr(0, dash) != me) return false;
  int pid = atoi(target.c_str() + dash + 1);
  if (pid <= 0 || pid == getpid()) return false;
  std::error_code a, b;
  auto theirs = fs::read_symlink("/proc/" + std::to_string(pid) + "/exe", a);
  auto mine = fs::read_symlink("/proc/self/exe", b);
  return !a && !b && theirs == mine;
}

namespace {
int g_claim_fd = -1;

bool SameExe(pid_t pid) {
  if (pid <= 0 || pid == getpid()) return false;
  if (kill(pid, 0) != 0) return false;
  std::error_code a, b;
  auto theirs = fs::read_symlink("/proc/" + std::to_string(pid) + "/exe", a);
  auto mine = fs::read_symlink("/proc/self/exe", b);
  return !a && !b && theirs == mine;
}

pid_t ClaimPid(int fd) {
  if (lseek(fd, 0, SEEK_SET) < 0) return 0;
  char buf[64] = {0};
  ssize_t n = ::read(fd, buf, sizeof(buf) - 1);
  if (n <= 0) return 0;
  return static_cast<pid_t>(atoi(buf));
}
}  // namespace

ProfileClaim ClaimProfile(const std::string& data_dir) {
  if (!MakeDirs(StateDir() + "/session-hold")) return ProfileClaim::Error;
  const std::string path = StateDir() + "/session-hold/" + FnvHex(Canon(data_dir)) + ".owner";
  int fd = ::open(path.c_str(), O_CREAT | O_RDWR | O_CLOEXEC, 0600);
  if (fd < 0) return ProfileClaim::Error;
  int dead_ms = 0;
  while (true) {
    if (LockHeldByQi(data_dir)) {
      ::close(fd);
      return ProfileClaim::Busy;
    }
    if (flock(fd, LOCK_EX | LOCK_NB) == 0) {
      char buf[64];
      int n = snprintf(buf, sizeof(buf), "%lld\n", static_cast<long long>(getpid()));
      if (ftruncate(fd, 0) != 0 || lseek(fd, 0, SEEK_SET) < 0 || ::write(fd, buf, n) != n) {
        flock(fd, LOCK_UN);
        ::close(fd);
        return ProfileClaim::Error;
      }
      g_claim_fd = fd;
      return ProfileClaim::Owner;
    }
    pid_t pid = ClaimPid(fd);
    if (pid > 0 && SameExe(pid)) {
      dead_ms = 0;
    } else {
      dead_ms += 50;
      if (dead_ms >= 5000) {
        ::close(fd);
        return ProfileClaim::Error;
      }
    }
    usleep(50000);
  }
}

void ReleaseProfileClaim() {
  if (g_claim_fd < 0) return;
  ::close(g_claim_fd);
  g_claim_fd = -1;
}

static bool Skip(const fs::path& rel) {
  static const std::set<std::string> dirs = {
      "Cache", "Code Cache", "GPUCache", "DawnGraphiteCache",
      "DawnWebGPUCache", "GrShaderCache", "ShaderCache", "GraphiteDawnCache",
      "component_crx_cache", "Crash Reports", "optimization_guide_model_store",
      "OptGuideOnDeviceModel", "Safe Browsing", "screen_ai", "CacheStorage",
      "extensions_crx_cache", "BrowserMetrics"};
  for (auto& part : rel) {
    if (dirs.count(part.string())) return true;
  }
  const std::string f = rel.filename().string();
  return f.rfind("Singleton", 0) == 0 || f == "RunningChromeVersion" ||
         f.find("BrowserMetrics") != std::string::npos;
}

bool CopyUserDataDir(const std::string& src,
                     const std::string& dest,
                     std::string* error) {
  if (!MakeDirs(dest)) {
    *error = "can't create " + dest;
    return false;
  }
  chmod(dest.c_str(), 0700);
  std::error_code ec;
  const fs::path base(src);
  auto it = fs::recursive_directory_iterator(src, ec);
  for (; !ec && it != fs::recursive_directory_iterator(); it.increment(ec)) {
    const fs::path rel = LexicalRel(it->path(), base);
    if (Escapes(rel)) {
      *error = "refusing to copy " + it->path().string();
      return false;
    }
    std::error_code se;
    const auto st = it->symlink_status(se);
    if (se) {
      *error = "stat " + rel.string() + ": " + se.message();
      return false;
    }
    if (Skip(rel)) {
      if (fs::is_directory(st) && !fs::is_symlink(st)) it.disable_recursion_pending();
      continue;
    }
    const fs::path out = fs::path(dest) / rel;
    if (Escapes(LexicalRel(out, dest))) {
      *error = "refusing to write " + out.string();
      return false;
    }
    std::error_code e2;
    if (fs::is_symlink(st)) {
      it.disable_recursion_pending();
      MakeDirs(out.parent_path().string());
      fs::copy_symlink(it->path(), out, e2);
    } else if (fs::is_directory(st)) {
      if (!MakeDirs(out.string())) e2 = std::make_error_code(std::errc::permission_denied);
    } else if (fs::is_regular_file(st)) {
      MakeDirs(out.parent_path().string());
      fs::copy_file(it->path(), out, fs::copy_options::overwrite_existing, e2);
    }
    if (e2) {
      *error = "copy " + rel.string() + ": " + e2.message();
      return false;
    }
  }
  if (ec) {
    *error = "walk " + src + ": " + ec.message();
    return false;
  }
  chmod(dest.c_str(), 0700);
  return true;
}

static std::string BackupOwner(const ChromeRoot& root) {
  if (root.id != "custom") return root.id;
  return "custom-" + FnvHex(Canon(root.dir));
}

static bool OwnedBackup(const std::string& name, const std::string& owner) {
  const std::string prefix = owner + "-";
  if (name.rfind(prefix, 0) != 0) return false;
  if (name.size() < prefix.size() + 8 + 4) return false;
  for (int i = 0; i < 8; ++i) {
    if (!isdigit(static_cast<unsigned char>(name[prefix.size() + i]))) return false;
  }
  return name.compare(prefix.size() + 8, 4, "-cef") == 0;
}

static bool MarkerMatches(const std::string& dest, const std::string& canon, bool custom) {
  const std::string marker = ReadAll(dest + "/.complete");
  const std::string key = "source: ";
  auto pos = marker.find(key);
  if (pos == std::string::npos) return !custom;
  std::string src = marker.substr(pos + key.size());
  auto nl = src.find('\n');
  if (nl != std::string::npos) src.resize(nl);
  return src == canon;
}

std::string BackupUserDataDir(const ChromeRoot& root, std::string* error) {
  const std::string base = DataDir() + "/chrome-backups";
  const std::string canon = Canon(root.dir);
  const std::string owner = BackupOwner(root);
  char day[16];
  time_t now = time(nullptr);
  strftime(day, sizeof(day), "%Y%m%d", localtime(&now));
  const std::string version = CEF_VERSION;
  const std::string short_version = version.substr(0, version.find('+'));
  const std::string dest = base + "/" + owner + "-" + day + "-cef" + short_version;
  if (Inside(canon, dest) || Inside(dest, canon)) {
    *error = "the backup would sit inside the profile";
    return "";
  }
  if (Exists(dest + "/.complete") &&
      MarkerMatches(dest, canon, root.id == "custom")) {
    return dest;
  }
  MakeDirs(base);
  std::error_code ec;
  fs::remove_all(dest, ec);
  if (!CopyUserDataDir(root.dir, dest, error)) {
    fs::remove_all(dest, ec);
    return "";
  }
  if (!LiveLockHolder(root.dir).empty()) {
    *error = root.label + " started while the backup was copying";
    fs::remove_all(dest, ec);
    return "";
  }
  {
    std::ofstream marker(dest + "/.complete");
    marker << "source: " << canon << "\n"
           << "Backup of " << root.dir << " made by Qi (CEF " << version
           << ") before it opened that profile.\n"
           << "Caches, locks and sockets were left out.\n"
           << "To restore: quit every browser using it, then\n"
           << "  broken=$(mktemp -d '" << root.dir << ".broken.XXXXXX') || exit 1\n"
           << "  mv '" << root.dir << "' \"$broken\" || exit 1\n"
           << "  cp -a '" << dest << "' '" << root.dir << "' || exit 1\n"
           << "  rm -f '" << root.dir << "/.complete'\n";
    marker.flush();
    if (!marker) {
      *error = "couldn't write " + dest + "/.complete";
      fs::remove_all(dest, ec);
      return "";
    }
  }
  std::vector<std::string> mine;
  for (auto& e : fs::directory_iterator(base, ec)) {
    std::string n = e.path().filename().string();
    if (OwnedBackup(n, owner)) mine.push_back(e.path().string());
  }
  std::sort(mine.begin(), mine.end());
  while (mine.size() > 3) {
    if (mine.front() != dest) fs::remove_all(mine.front(), ec);
    mine.erase(mine.begin());
  }
  return dest;
}

// Chrome stores this pref twice more as hashed strings. Only the integer
// value is the setting.
size_t FindStartupPref(const std::string& text) {
  const std::string key = "\"restore_on_startup\"";
  size_t from = 0;
  while (from < text.size()) {
    auto pos = text.find(key, from);
    if (pos == std::string::npos) return pos;
    auto colon = text.find(':', pos + key.size());
    if (colon == std::string::npos || colon > pos + key.size() + 8) {
      from = pos + key.size();
      continue;
    }
    size_t i = colon + 1;
    while (i < text.size() && std::isspace(static_cast<unsigned char>(text[i]))) ++i;
    if (i < text.size() &&
        (std::isdigit(static_cast<unsigned char>(text[i])) || text[i] == '-'))
      return pos;
    from = pos + key.size();
  }
  return std::string::npos;
}

bool WritePrivate(const std::string& path, const std::string& body);

bool PatchStartupPref(const std::string& path, bool had, int value) {
  if (!Exists(path)) return true;
  std::string text = ReadAll(path);
  const std::string key = "\"restore_on_startup\"";
  auto pos = FindStartupPref(text);
  std::string edited = text;
  if (!had) {
    if (pos == std::string::npos) return true;
    size_t start = pos;
    while (start > 0 &&
           (edited[start - 1] == ' ' || edited[start - 1] == '\n' || edited[start - 1] == '\t'))
      --start;
    bool comma_before = start > 0 && edited[start - 1] == ',';
    if (comma_before) --start;
    auto end = edited.find_first_of(",}", pos + key.size());
    if (end == std::string::npos) return false;
    if (!comma_before && edited[end] == ',') ++end;
    edited.erase(start, end - start);
  } else if (pos == std::string::npos) {
    auto s = edited.find("\"session\"");
    if (s == std::string::npos) return false;
    auto brace = edited.find('{', s);
    if (brace == std::string::npos) return false;
    edited.insert(brace + 1, "\"restore_on_startup\":" + std::to_string(value) + ",");
  } else {
    auto colon = edited.find(':', pos + key.size());
    if (colon == std::string::npos) return false;
    auto num = edited.find_first_of("-0123456789", colon + 1);
    if (num == std::string::npos || num > colon + 16) return false;
    size_t end = num;
    if (edited[end] == '-') ++end;
    while (end < edited.size() && isdigit(static_cast<unsigned char>(edited[end]))) ++end;
    edited.replace(num, end - num, std::to_string(value));
  }
  if (edited == text) return true;
  auto check = CefParseJSON(edited, JSON_PARSER_RFC);
  if (!check || check->GetType() != VTYPE_DICTIONARY) return false;
  if (had) {
    auto session = check->GetDictionary()->GetDictionary("session");
    if (!session || !session->HasKey("restore_on_startup") ||
        session->GetInt("restore_on_startup") != value)
      return false;
  }
  return WritePrivate(path, edited);
}

// A new 0600 file in the profile directory, then an atomic rename. The
// temporary name is created with O_EXCL | O_NOFOLLOW so a symlink there is
// not a place we write.
bool WritePrivate(const std::string& path, const std::string& body) {
  auto slash = path.find_last_of('/');
  if (slash == std::string::npos || slash == 0) return false;
  int dirfd = ::open(path.substr(0, slash).c_str(),
                     O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (dirfd < 0) return false;
  std::string base = path.substr(slash + 1);
  std::string tmpname;
  int fd = -1;
  for (int i = 0; i < 32 && fd < 0; ++i) {
    tmpname = ".qi-" + std::to_string(getpid()) + "-" + std::to_string(i) + "-" + base;
    fd = ::openat(dirfd, tmpname.c_str(),
                  O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY | O_CLOEXEC, 0600);
  }
  if (fd < 0) {
    ::close(dirfd);
    return false;
  }
  auto fail = [&]() {
    ::close(fd);
    ::unlinkat(dirfd, tmpname.c_str(), 0);
    ::close(dirfd);
    return false;
  };
  const char* p = body.data();
  size_t left = body.size();
  while (left) {
    ssize_t n = ::write(fd, p, left);
    if (n < 0) {
      if (errno == EINTR) continue;
      return fail();
    }
    p += n;
    left -= static_cast<size_t>(n);
  }
  if (::fsync(fd) != 0) return fail();
  if (::close(fd) != 0) {
    fd = -1;
    ::unlinkat(dirfd, tmpname.c_str(), 0);
    ::close(dirfd);
    return false;
  }
  fd = -1;
  if (::renameat(dirfd, tmpname.c_str(), dirfd, base.c_str()) != 0) {
    ::unlinkat(dirfd, tmpname.c_str(), 0);
    ::close(dirfd);
    return false;
  }
  ::close(dirfd);
  return true;
}

bool WritePrefSidecar() {
  if (!MakeDirs(StateDir() + "/session-hold")) return false;
  std::string body;
  for (auto& p : StartupPrefs())
    body += p.path + '\t' + (p.had ? "1" : "0") + '\t' + std::to_string(p.value) + '\n';
  int fd = ::open(PrefSidecarPath().c_str(), O_CREAT | O_WRONLY | O_TRUNC | O_CLOEXEC, 0600);
  if (fd < 0) return false;
  const char* p = body.data();
  size_t left = body.size();
  bool ok = true;
  while (left) {
    ssize_t n = ::write(fd, p, left);
    if (n < 0) {
      if (errno == EINTR) continue;
      ok = false;
      break;
    }
    p += n;
    left -= static_cast<size_t>(n);
  }
  if (ok && ::fsync(fd) != 0) ok = false;
  if (::close(fd) != 0) ok = false;
  return ok;
}

bool ApplyStartupPrefFile(const std::string& path) {
  std::ifstream in(path);
  if (!in) return false;
  bool ok = true;
  std::vector<std::string> left;
  std::string line;
  while (std::getline(in, line)) {
    auto t1 = line.find('\t');
    if (t1 == std::string::npos) continue;
    auto t2 = line.find('\t', t1 + 1);
    if (t2 == std::string::npos) continue;
    std::string pref = line.substr(0, t1);
    if (ProfileRootBusy(pref)) {
      left.push_back(line);
      ok = false;
      continue;
    }
    bool had = line.substr(t1 + 1, t2 - t1 - 1) == "1";
    int value = std::atoi(line.c_str() + t2 + 1);
    if (!PatchStartupPref(pref, had, value)) {
      left.push_back(line);
      ok = false;
    }
  }
  in.close();
  if (ok) {
    std::error_code ec;
    fs::remove(path, ec);
    return true;
  }
  KeepLines(path, left);
  return false;
}

void RecoverPrefSidecars() {
  std::error_code ec;
  const fs::path dir = StateDir() + "/session-hold";
  if (!fs::is_directory(dir, ec)) return;
  std::vector<std::string> dead;
  for (auto& e : fs::directory_iterator(dir, ec)) {
    std::string name = e.path().filename().string();
    const std::string suffix = ".prefs";
    if (name.size() <= suffix.size() ||
        name.compare(name.size() - suffix.size(), suffix.size(), suffix) != 0)
      continue;
    std::string digits = name.substr(0, name.size() - suffix.size());
    bool numeric = !digits.empty();
    for (char c : digits)
      numeric = numeric && std::isdigit(static_cast<unsigned char>(c));
    if (!numeric) continue;
    long pid = std::atol(digits.c_str());
    if (pid > 0 && pid != getpid() && kill(static_cast<pid_t>(pid), 0) == 0) continue;
    if (pid > 0 && pid != getpid() && errno != ESRCH) continue;
    dead.push_back(e.path().string());
  }
  for (auto& path : dead) ApplyStartupPrefFile(path);
}

bool RememberStartupPrefs(const std::string& data_dir) {
  RecoverPrefSidecars();
  StartupPrefs().clear();
  std::error_code ec;
  for (auto& e : fs::directory_iterator(data_dir, ec)) {
    std::error_code se;
    if (!e.is_directory(se) || se) continue;
    if (SkipDot(e.path().filename().string())) continue;
    StartupPref p;
    p.folder = e.path().filename().string();
    p.path = e.path().string() + "/Preferences";
    if (!Exists(p.path)) continue;
    auto v = CefParseJSON(ReadAll(p.path), JSON_PARSER_RFC);
    if (v && v->GetType() == VTYPE_DICTIONARY) {
      if (auto session = v->GetDictionary()->GetDictionary("session")) {
        if (session->HasKey("restore_on_startup")) {
          p.had = true;
          p.value = session->GetInt("restore_on_startup");
        }
      }
    }
    StartupPrefs().push_back(p);
  }
  if (ec) return false;
  return WritePrefSidecar();
}

const std::vector<std::pair<std::string, int>>& OpenStartupPrefValues() {
  static std::vector<std::pair<std::string, int>> out;
  out.clear();
  for (auto& p : StartupPrefs()) {
    if (p.had) out.emplace_back(p.folder, p.value);
  }
  return out;
}

void RestoreStartupPrefsOnDisk() {
  bool ok = true;
  for (auto& p : StartupPrefs()) ok = PatchStartupPref(p.path, p.had, p.value) && ok;
  if (ok) {
    std::error_code ec;
    fs::remove(PrefSidecarPath(), ec);
  }
}

bool HoldBrowserSessions(const std::string& data_dir) {
  RecoverDeadManifests();
  ReleaseBrowserSessions(data_dir);
  std::error_code ec;
  if (!MakeDirs(StateDir() + "/session-hold")) return false;
  for (auto& e : fs::directory_iterator(data_dir, ec)) {
    std::error_code se;
    if (!e.is_directory(se) || se) continue;
    if (SkipDot(e.path().filename().string())) continue;
    const std::string profile = e.path().string();
    bool any = false;
    for (const char* name : kSessionNames)
      any = any || Exists(profile + "/" + name);
    if (!any) continue;
    const std::string hold = HoldDir(profile);
    if (!MakeDirs(hold)) {
      ReleaseBrowserSessions(data_dir);
      return false;
    }
    for (const char* name : kSessionNames) {
      const fs::path src = fs::path(profile) / name;
      if (!Exists(src.string())) continue;
      const fs::path held = fs::path(hold) / name;
      if (!NoteHeld(src.string(), held.string())) {
        std::cerr << "qi-cef: couldn't record " << src.string() << "\n";
        ReleaseBrowserSessions(data_dir);
        return false;
      }
      se.clear();
      fs::rename(src, held, se);
      if (se) {
        std::cerr << "qi-cef: couldn't set aside " << src.string() << ": " << se.message()
                  << "\n";
        ReleaseBrowserSessions(data_dir);
        return false;
      }
    }
  }
  if (ec) {
    ReleaseBrowserSessions(data_dir);
    return false;
  }
  HeldRoot() = data_dir;
  return true;
}

void ReleaseBrowserSessions(const std::string& data_dir) {
  std::error_code ec;
  bool ok = true;
  if (Exists(data_dir)) {
    for (auto& e : fs::directory_iterator(data_dir, ec)) {
      std::error_code se;
      if (!e.is_directory(se) || se) continue;
      if (SkipDot(e.path().filename().string())) continue;
      ok = ReleaseOne(e.path().string()) && ok;
    }
  }
  if (ok) {
    fs::remove(ManifestPath(), ec);
  }
  if (HeldRoot() == data_dir) HeldRoot().clear();
}

}  // namespace qi
