// qi-cef: Qi on Chromium (CEF Chrome runtime, Chrome style).
//
//   qi-cef [url...]                    last-used profile of Chromium
//   qi-cef --profile="Work" [url]       a profile by name or folder
//   qi-cef --profile-directory="Profile 1"
//   qi-cef --space=2                    the profile of Qi Space 2
//   qi-cef --browser=google-chrome      another browser's profiles
//   qi-cef --picker                     choose a profile
//   qi-cef --list-profiles              print them and exit
//   qi-cef --snapshot                   run a throwaway copy (use while
//                                           Chrome/Chromium is open)
//   qi-cef --install-extension=<id>     open its Web Store page
//   qi-cef --extensions                 chrome://extensions
#include <cstdlib>
#include <unistd.h>

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#include "include/cef_app.h"
#include "include/cef_parser.h"
#include "include/cef_version.h"
#include "qi.h"

namespace qi {
CefRefPtr<CefApp> CreateApp();
}

using namespace qi;

static std::string ReadAll(const std::string& path) {
  std::ifstream f(path);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

static void Tell(const std::string& msg) {
  std::cerr << "qi-cef: " << msg << "\n";
  if (!isatty(2)) {
    std::string cmd = "notify-send -a Qi 'Qi (CEF)' \"$QI_MSG\" 2>/dev/null";
    setenv("QI_MSG", msg.c_str(), 1);
    if (system(cmd.c_str()) != 0) {
    }
  }
}

static int RunBrowser(int argc, char* argv[], const CefMainArgs& main_args,
                      CefRefPtr<CefApp> app);

static std::string LastUsed(const std::string& dir) {
  auto v = CefParseJSON(ReadAll(dir + "/Local State"), JSON_PARSER_RFC);
  if (v && v->GetType() == VTYPE_DICTIONARY) {
    if (auto p = v->GetDictionary()->GetDictionary("profile")) {
      std::string last = p->GetString("last_used");
      if (!last.empty() && Exists(dir + "/" + last)) return last;
    }
  }
  return "Default";
}

// Zygote children run with --change-stack-guard-on-fork, so the canary
// main() saved before the fork no longer matches by the time it returns,
// and glibc aborts with "stack smashing detected". main() therefore has no
// stack protector, and sub-processes leave through exit() rather than
// returning through it.
__attribute__((no_stack_protector)) int main(int argc, char* argv[]) {
  CefMainArgs main_args(argc, argv);
  CefRefPtr<CefApp> app = CreateApp();

  // Sub-processes (renderer, GPU, ...) exit here.
  int code = CefExecuteProcess(main_args, app, nullptr);
  if (code >= 0) {
    app = nullptr;
    std::exit(code);
  }
  return RunBrowser(argc, argv, main_args, app);
}

static int RunBrowser(int argc, char* argv[], const CefMainArgs& main_args,
                      CefRefPtr<CefApp> app) {
  MigrateLegacyDirs();

  CefRefPtr<CefCommandLine> cl = CefCommandLine::CreateCommandLine();
  cl->InitFromArgv(argc, argv);

  if (cl->HasSwitch("version")) {
    std::cout << "qi-cef (CEF " << CEF_VERSION << ")\n";
    return 0;
  }

  // Which browser's user data dir.
  ChromeRoot root;
  if (cl->HasSwitch("browser")) {
    root = RootById(cl->GetSwitchValue("browser"));
    if (root.id.empty()) {
      Tell("unknown --browser " + cl->GetSwitchValue("browser").ToString() +
           " (chromium, google-chrome, google-chrome-beta, brave, qi)");
      return 2;
    }
  } else if (cl->HasSwitch("user-data-dir")) {
    root = {"custom", "Chrome", cl->GetSwitchValue("user-data-dir"), ""};
  } else {
    root = KnownRoots().front();
  }

  if (cl->HasSwitch("list-profiles")) {
    for (auto& r : KnownRoots()) {
      std::cout << r.label << "  " << r.dir << "\n";
      SetActiveRoot(r, r.dir);
      for (auto& p : ProfilesIn(r))
        std::cout << "  " << p.dir << "\t" << p.name
                  << (p.gaia_name.empty() ? "" : "\t" + p.gaia_name) << "\n";
    }
    return 0;
  }

  // Safety first: never two browsers on one profile, never without a backup.
  std::string data_dir = root.dir;
  const bool snapshot = cl->HasSwitch("snapshot");
  if (root.id == "qi") {
    MakeDirs(root.dir);
  } else if (snapshot) {
    data_dir = HomeDir() + "/.cache/qi-cef/snapshot-" + root.id;
    std::error_code ec;
    if (!cl->HasSwitch("keep-snapshot") || !Exists(data_dir)) {
      std::filesystem::remove_all(data_dir, ec);
      std::string err;
      if (!CopyUserDataDir(root.dir, data_dir, &err)) {
        Tell("couldn't copy " + root.dir + ": " + err);
        return 4;
      }
    }
  } else if (LockHeldByQi(root.dir)) {
    // Qi (CEF) already runs this profile: CefInitialize below hands it our
    // command line (OnAlreadyRunningAppRelaunch) and returns.
  } else {
    std::string holder = LiveLockHolder(root.dir);
    if (!holder.empty()) {
      Tell(root.label + " is open on this profile (" + holder +
           "). Quit it first, or run `qi-cef --snapshot` to use a copy.");
      return 3;
    }
    if (!cl->HasSwitch("no-backup")) {
      std::string err;
      std::string backup = BackupUserDataDir(root, &err);
      if (backup.empty()) {
        Tell("couldn't back up " + root.dir + " (" + err +
             "), so it wasn't opened.");
        return 4;
      }
      std::cerr << "qi-cef: backup at " << backup << "\n";
    }
  }
  SetActiveRoot(root, data_dir);

  // Which profile the first window (and CefSettings.cache_path) uses.
  std::string startup;
  for (const char* key : {"profile-directory", "profile"}) {
    if (startup.empty() && cl->HasSwitch(key))
      startup = ResolveProfileDir(cl->GetSwitchValue(key));
  }
  if (startup.empty() && cl->HasSwitch("space"))
    startup = ProfileForSpace(atoi(cl->GetSwitchValue("space").ToString().c_str()) - 1);
  if (startup.empty()) startup = LastUsed(data_dir);
  SetStartupProfile(startup);

  // Chrome writes its version beside the profiles; keep the browser's own
  // value so it doesn't treat the next start as a downgrade.
  const std::string last_version_path = data_dir + "/Last Version";
  const std::string last_version = ReadAll(last_version_path);

  const Theme& theme = CurrentTheme();
  CefSettings settings;
  CefString(&settings.root_cache_path) = data_dir;
  CefString(&settings.cache_path) = data_dir + "/" + startup;
  settings.persist_session_cookies = true;
  settings.background_color = theme.background;
  MakeDirs(StateDir());
  CefString(&settings.log_file) = StateDir() + "/cef.log";
  settings.log_severity = LOGSEVERITY_WARNING;

  if (!CefInitialize(main_args, settings, app, nullptr)) {
    // Usually: Qi (CEF) already runs this dir and got our command line.
    return CefGetExitCode();
  }
  CefRunMessageLoop();
  CefShutdown();

  if (!snapshot && !last_version.empty() &&
      ReadAll(last_version_path) != last_version) {
    std::ofstream(last_version_path) << last_version;
  }
  return 0;
}
