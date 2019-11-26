# symbol-scrapers
A bunch of scripts to scrape symbols from Linux distributions

Each scripts needs to be run in its own directory as it uses the current
working directory to unpack and process debug-information.

Before running the scripts the following environment variables need to be set:

* `DUMP_SYMS` - The path to the `dump_syms` tool, the version built as part
  of mozilla-central is currently required as the upstream Breakpad version
  lacks some important functionality
* `SYMBOLS_API_TOKEN` - An API token for https://symbols.mozilla.org
* `CRASHSTATS_API_TOKEN` - An API token for https://crash-stats.mozilla.org, it
  needs the reprocess permission set in order to reprocess crashes
