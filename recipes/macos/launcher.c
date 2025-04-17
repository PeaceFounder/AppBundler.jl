#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <libgen.h>
#include <string.h>

#include <mach-o/dyld.h>

const int PATH_MAX = 1024;

int main(void) {
  // Hardcoded relative path to the executable
  //char *relativeExecutablePath = "main";  
  char *relativeExecutablePath = "../Libraries/main";  

  char launcherPath[PATH_MAX];
  uint32_t size = sizeof(launcherPath);

  // Get the executable's path
  if (_NSGetExecutablePath(launcherPath, &size) != 0) {
    printf("Buffer too small; need size %u\n", size);
    return 1;
  }

  // Extract the directory from the launcher's path
  char *launcherDir = dirname(launcherPath);

  // Construct the absolute path of the executable
  char executablePath[PATH_MAX];
  snprintf(executablePath, sizeof(executablePath), "%s/%s", launcherDir, relativeExecutablePath);

  // Prepare the arguments array for the new process
  // The first argument should be the name of the executable
  // The rest of the arguments are passed to the new process
  char *argv[] = {
    executablePath,
    NULL
  };

  // Replace the current process with the new process
  execvp(executablePath, argv);

  // If execvp returns, an error occurred
  perror("Error launching process");
  return EXIT_FAILURE;
}
