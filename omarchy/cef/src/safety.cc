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
//   The newest three are kept.
#include <signal.h>
#include <unistd.h>

#include <algorithm>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <set>

#include "include/cef_version.h"
#include "qi.h"

namespace fs = std::filesystem;

namespace qi {

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
  std::error_code ec;
  fs::create_directories(dest, ec);
  if (ec) {
    *error = "can't create " + dest + ": " + ec.message();
    return false;
  }
  auto it = fs::recursive_directory_iterator(
      src, fs::directory_options::skip_permission_denied, ec);
  for (; !ec && it != fs::recursive_directory_iterator(); it.increment(ec)) {
    const fs::path rel = fs::relative(it->path(), src);
    if (Skip(rel)) {
      if (it->is_directory() && !it->is_symlink()) it.disable_recursion_pending();
      continue;
    }
    const fs::path out = fs::path(dest) / rel;
    std::error_code e2;
    auto st = it->symlink_status(e2);
    if (fs::is_symlink(st)) {
      fs::copy_symlink(it->path(), out, e2);
    } else if (fs::is_directory(st)) {
      fs::create_directories(out, e2);
    } else if (fs::is_regular_file(st)) {
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
  return true;
}

std::string BackupUserDataDir(const ChromeRoot& root, std::string* error) {
  const std::string base = DataDir() + "/chrome-backups";
  char day[16];
  time_t now = time(nullptr);
  strftime(day, sizeof(day), "%Y%m%d", localtime(&now));
  const std::string version = CEF_VERSION;
  const std::string short_version = version.substr(0, version.find('+'));
  const std::string dest =
      base + "/" + root.id + "-" + day + "-cef" + short_version;
  if (Exists(dest + "/.complete")) return dest;
  MakeDirs(base);
  std::error_code ec;
  fs::remove_all(dest, ec);
  if (!CopyUserDataDir(root.dir, dest, error)) return "";
  std::ofstream(dest + "/.complete")
      << "Backup of " << root.dir << " made by Qi (CEF " << version
      << ") before it opened that profile.\n"
      << "Caches, locks and sockets were left out.\n"
      << "To restore: quit every browser using it, then\n"
      << "  mv '" << root.dir << "' '" << root.dir << ".broken'\n"
      << "  cp -a '" << dest << "' '" << root.dir << "'\n"
      << "  rm '" << root.dir << "/.complete'\n";
  // Keep the newest three of this browser.
  std::vector<std::string> mine;
  for (auto& e : fs::directory_iterator(base, ec)) {
    std::string n = e.path().filename().string();
    if (n.rfind(root.id + "-", 0) == 0) mine.push_back(e.path().string());
  }
  std::sort(mine.begin(), mine.end());
  while (mine.size() > 3) {
    if (mine.front() != dest) fs::remove_all(mine.front(), ec);
    mine.erase(mine.begin());
  }
  return dest;
}

}  // namespace qi
