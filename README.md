# GitHub Runner Utilities

Scripts for setting up and managing pools of self-hosted GitHub runners on NOAA HPC.

To use these scripts, you must have admin access to the repository.

**Using self-hosted GitHub runners can pose a security risk. Please ensure any GitHub actions using self-hosted runners are properly protected from running arbitrary code from pull requests without appropriate approval.**

To use the corresponding runners, add the following to the GitHub actions you wish to run on HPC:
```
runs-on: $machine
```

# Usage

## Initialize Runner Directory

The first step is to initialize the runner root directory. This will create the root directory, download a copy of the GitHub runner tarball, initialize the connected repo and which host you wish to run the runners on, and copy all the other scripts to the target directory. The host must be a head node with internet access.

```
./init_runner_dir.sh [$runner_root [$repo [$hostname]]]
```

This will initialize `$runner_root` to hold self-hosted runners for `$repo`.

If arguments are not provided, the user will be prompted for them. Additionally, if `$runner_root` already exists, the user will be prompted whether to `delete` the existing directory, `use` the existing directory, or `abort`.
- If `delete` is selected, any runners that already exist will first be stopped and destroyed, to avoid orphaned runners
- If `use` is selected, the assigned repo and hostname, as well as any runners, will be preserved. All of the utility scripts will be updated with the versions from the current directory.

Once initialized, all of the other scripts are run from that directory, not from the source directory. All of these scripts will only run on the assigned host; if you run them on any other host, the script will collect the necessary information, then SSH into the correct host and execute the script there. This ensures the process IDs of the runners stays consistent so they can be managed.

Short descriptions of all the available actions (full descriptions available further below):
- `create_runners.sh`: Create, register, and start additional GitHub runners
- `destroy_runners.sh`: Stop, unregister, and delete GitHub runners
- `runner_watchdog.sh`: Confirm each runner is running, and start it if not
- `stop_runners.sh`: Stop a runner without destroying it
- `start_runners.sh`: Start previously stopped runners

## Create Runners

```
${runner_root}/create_runners.sh [$num_new]
```

Creates and registers additional GH runners. Runners will have a label corresponding to the machine (e.g. ursa, hercules, etc.). Runner names on each machine will be assigned sequentially starting from 0 with three-digit padding: ursa_000, ursa_001, etc. If `$num_new` is not provided on the command line, the user will be prompted.

Create runners will attempt to acquire a GitHub token automatically using the GitHub CLI (`gh`). To work, `gh` must be in your current path (usually by loading a module), you must be authenticated, and you must have owner permissions on the target repository. If this attempt fails, you will be prompted to provide a key manually.

Once created, the new runners will be started. To make sure the runners are automatically restarted if the processes should be killed, add `${runner_root}/runner_watchdog.sh` to your crontab/scron to run at regular intervals.

## Destroy Runners

```
${runner_root}/create_runners.sh [$num_destroy|all]
```

Stops, unregisters, and deletes GH runners. Runners will be destroyed in the reverse order they were created (i.e. the highest numbered one first). If `$num_destroy` is not provided, the user will be prompted. `all` is a valid value (either on the CLI or in response to a prompt).

If all runners are destroyed, the user will be asked whether they wish to delete the entire `$runner_root` directory.

## Monitor Runners

```
${runner_root}/runner_watchdog.sh
```

Iterates over all runners checks whether their recorded process ID is still running, and start the runner if not. This is called automatically after starting of creating runners, and can be added to your cron/scron to act as a pseudo-daemon to keep runners up.

```cron
*/5 * * * * /path/to/runner_root/runner_watchdog.sh >> /path/to/runner_root_runner_watchdog.log 2>&1
```

## Stop Runners

```
${runner_root}/stop_runners.sh [$runner_1|all [$runner_2 [...]]]
```

Stops the requested runners, and mark them as stopped so the watchdog will not restart them. Runner names may either be the full runner name (`${machine}_###`) or just the number of the runner(s). If the first argument is `all`, all runners will be stopped and any other arguments are ignored.

Stopped runners are *not* deregistered. They will still appear on GitHub as "offline". To remove the runners from GitHub, use `destroy_runners.sh` instead.

## Start Runners

```
${runner_root}/stop_runners.sh [$runner_1|all [$runner_2 [...]]]
```

Remove any stopped markers from the specified runners, then call watchdog to restart them. Runner names may either be the full runner name (`${machine}_###`) or just the number of the runner(s). If the first argument is `all`, all runners will be started and any other arguments are ignored.
