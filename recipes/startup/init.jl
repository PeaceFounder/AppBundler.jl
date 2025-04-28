mkpath(ENV["USER_DATA"])

LOGFILE_PATH = joinpath(ENV["USER_DATA"], "session.log")
rm(LOGFILE_PATH, force=true)
logfile = open(LOGFILE_PATH, "w")
redirect_stdout(logfile)
redirect_stderr(logfile)
