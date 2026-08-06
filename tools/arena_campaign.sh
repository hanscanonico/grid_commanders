#!/bin/bash
# AR5's campaign: every block searched separately, each from the shipped base.
#
# Separately and from one base is R7's requirement — a block that started from
# the previous block's champion would fold two answers into one number and there
# would be no way to say which dial bought what. Composing the winners is a
# separate reading, taken afterwards.
#
# Cheapest blocks first, so a campaign that is interrupted has still answered
# something. Every block is resumable: re-running this script skips the shards
# already on disk and costs seconds for the ones already finished.
set -u

BLOCKS="join formation threat combat production economy economy_map"
LOG=reports/ai_arena/search/campaign.log
mkdir -p "$(dirname "$LOG")"

echo "=== campaign start $(date '+%F %T') ===" | tee -a "$LOG"
for block in $BLOCKS; do
	started=$(date +%s)
	echo "--- $block: start $(date '+%F %T') ---" | tee -a "$LOG"
	tools/arena_search.py --block="$block" --out="ai_arena/search/$block" >> "$LOG" 2>&1
	status=$?
	elapsed=$(( ($(date +%s) - started) / 60 ))
	echo "--- $block: exit $status after ${elapsed}m ---" | tee -a "$LOG"
done
echo "=== campaign end $(date '+%F %T') ===" | tee -a "$LOG"
