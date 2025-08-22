#!/bin/bash

clear

# User input section
echo "Please enter the following configuration details:"
echo

read -p "Enter value for EVENT: " EVENT
echo
read -p "Enter value for TABLE: " TABLE
echo
read -p "Enter value for VALUE_X1: " VALUE_X1
echo
read -p "Enter value for VALUE_Y1: " VALUE_Y1
echo
read -p "Enter value for VALUE_X2: " VALUE_X2
echo
read -p "Enter value for VALUE_Y2: " VALUE_Y2
echo
read -p "Enter value for FUNC_1: " FUNC_1
echo
read -p "Enter value for FUNC_2: " FUNC_2
echo
read -p "Enter value for MODEL: " MODEL

# Export variables
export EVENT TABLE VALUE_X1 VALUE_Y1 VALUE_X2 VALUE_Y2 FUNC_1 FUNC_2 MODEL

# Show configuration summary
echo
echo "╔════════════════════════════════════════════╗"
echo "║          CONFIGURATION SUMMARY             ║"
echo "╠════════════════════════════════════════════╣"
echo "║ EVENT: $EVENT"
echo "║ TABLE: $TABLE"
echo "║ Coordinates: ($VALUE_X1,$VALUE_Y1) ($VALUE_X2,$VALUE_Y2)"
echo "║ Functions: $FUNC_1, $FUNC_2"
echo "║ Model: $MODEL"
echo "╚════════════════════════════════════════════╝"
echo

# Data loading section
echo "Loading soccer data into BigQuery tables..."
bq load --source_format=NEWLINE_DELIMITED_JSON --autodetect $DEVSHELL_PROJECT_ID:soccer.$EVENT gs://spls/bq-soccer-analytics/events.json && \
echo "✓ Events data loaded" || echo "✗ Failed to load events"

bq load --source_format=CSV --autodetect $DEVSHELL_PROJECT_ID:soccer.$TABLE gs://spls/bq-soccer-analytics/tags2name.csv && \
echo "✓ Tags data loaded" || echo "✗ Failed to load tags"

bq load --autodetect --source_format=NEWLINE_DELIMITED_JSON $DEVSHELL_PROJECT_ID:soccer.competitions gs://spls/bq-soccer-analytics/competitions.json && \
echo "✓ Competitions data loaded" || echo "✗ Failed to load competitions"

bq load --autodetect --source_format=NEWLINE_DELIMITED_JSON $DEVSHELL_PROJECT_ID:soccer.matches gs://spls/bq-soccer-analytics/matches.json && \
echo "✓ Matches data loaded" || echo "✗ Failed to load matches"

bq load --autodetect --source_format=NEWLINE_DELIMITED_JSON $DEVSHELL_PROJECT_ID:soccer.teams gs://spls/bq-soccer-analytics/teams.json && \
echo "✓ Teams data loaded" || echo "✗ Failed to load teams"

bq load --autodetect --source_format=NEWLINE_DELIMITED_JSON $DEVSHELL_PROJECT_ID:soccer.players gs://spls/bq-soccer-analytics/players.json && \
echo "✓ Players data loaded" || echo "✗ Failed to load players"

echo
echo "All data loaded successfully!"
echo

# Query execution section
echo "Analyzing penalty kick success rates..."
bq query --use_legacy_sql=false \
"
SELECT
playerId,
(Players.firstName || ' ' || Players.lastName) AS playerName,
COUNT(id) AS numPKAtt,
SUM(IF(101 IN UNNEST(tags.id), 1, 0)) AS numPKGoals,
SAFE_DIVIDE(
SUM(IF(101 IN UNNEST(tags.id), 1, 0)),
COUNT(id)
) AS PKSuccessRate
FROM
\`soccer.$EVENT\` Events
LEFT JOIN
\`soccer.players\` Players ON
Events.playerId = Players.wyId
WHERE
eventName = 'Free Kick' AND
subEventName = 'Penalty'
GROUP BY
playerId, playerName
HAVING
numPkAtt >= 5
ORDER BY
PKSuccessRate DESC, numPKAtt DESC
"

echo
echo "📊 Analyzing shot distances and goal percentages..."
bq query --use_legacy_sql=false \
"
WITH
Shots AS
(
SELECT
*,
(101 IN UNNEST(tags.id)) AS isGoal,
SQRT(
POW(
    (100 - positions[ORDINAL(1)].x) * $VALUE_X1/$VALUE_Y1,
    2) +
POW(
    (60 - positions[ORDINAL(1)].y) * $VALUE_X2/$VALUE_Y2,
    2)
 ) AS shotDistance
FROM
\`soccer.$EVENT\`
WHERE
eventName = 'Shot' OR
(eventName = 'Free Kick' AND subEventName IN ('Free kick shot', 'Penalty'))
)
SELECT
ROUND(shotDistance, 0) AS ShotDistRound0,
COUNT(*) AS numShots,
SUM(IF(isGoal, 1, 0)) AS numGoals,
AVG(IF(isGoal, 1, 0)) AS goalPct
FROM
Shots
WHERE
shotDistance <= 50
GROUP BY
ShotDistRound0
ORDER BY
ShotDistRound0
"

# Model creation section
echo
echo "Creating machine learning model for shot predictions..."
bq query --use_legacy_sql=false \
"
CREATE MODEL \`$MODEL\`
OPTIONS(
model_type = 'LOGISTIC_REG',
input_label_cols = ['isGoal']
) AS
SELECT
Events.subEventName AS shotType,
(101 IN UNNEST(Events.tags.id)) AS isGoal,
\`$FUNC_1\`(Events.positions[ORDINAL(1)].x,
Events.positions[ORDINAL(1)].y) AS shotDistance,
\`$FUNC_2\`(Events.positions[ORDINAL(1)].x,
Events.positions[ORDINAL(1)].y) AS shotAngle
FROM
\`soccer.$EVENT\` Events
LEFT JOIN
\`soccer.matches\` Matches ON
Events.matchId = Matches.wyId
LEFT JOIN
\`soccer.competitions\` Competitions ON
Matches.competitionId = Competitions.wyId
WHERE
Competitions.name != 'World Cup' AND
(
eventName = 'Shot' OR
(eventName = 'Free Kick' AND subEventName IN ('Free kick shot', 'Penalty'))
) AND
\`$FUNC_2\`(Events.positions[ORDINAL(1)].x,
Events.positions[ORDINAL(1)].y) IS NOT NULL
;
" && echo "✓ Model created successfully" || echo "✗ Model creation failed"

# Prediction section
echo
echo "Running predictions using the created model..."
bq query --use_legacy_sql=false \
"
SELECT
predicted_isGoal_probs[ORDINAL(1)].prob AS predictedGoalProb,
* EXCEPT (predicted_isGoal, predicted_isGoal_probs),
FROM
ML.PREDICT(
MODEL \`$MODEL\`, 
(
 SELECT
     Events.playerId,
     (Players.firstName || ' ' || Players.lastName) AS playerName,
     Teams.name AS teamName,
     CAST(Matches.dateutc AS DATE) AS matchDate,
     Matches.label AS match,
     CAST((CASE
         WHEN Events.matchPeriod = '1H' THEN 0
         WHEN Events.matchPeriod = '2H' THEN 45
         WHEN Events.matchPeriod = 'E1' THEN 90
         WHEN Events.matchPeriod = 'E2' THEN 105
         ELSE 120
         END) +
         CEILING(Events.eventSec / 60) AS INT64)
         AS matchMinute,
     Events.subEventName AS shotType,
     (101 IN UNNEST(Events.tags.id)) AS isGoal,
     \`soccer.$FUNC_1\`(Events.positions[ORDINAL(1)].x,
             Events.positions[ORDINAL(1)].y) AS shotDistance,
     \`soccer.$FUNC_2\`(Events.positions[ORDINAL(1)].x,
             Events.positions[ORDINAL(1)].y) AS shotAngle
 FROM
     \`soccer.$EVENT\` Events
 LEFT JOIN
     \`soccer.matches\` Matches ON
             Events.matchId = Matches.wyId
 LEFT JOIN
     \`soccer.competitions\` Competitions ON
             Matches.competitionId = Competitions.wyId
 LEFT JOIN
     \`soccer.players\` Players ON
             Events.playerId = Players.wyId
 LEFT JOIN
     \`soccer.teams\` Teams ON
             Events.teamId = Teams.wyId
 WHERE
     Competitions.name = 'World Cup' AND
     (
         eventName = 'Shot' OR
         (eventName = 'Free Kick' AND subEventName IN ('Free kick shot'))
     ) AND
     (101 IN UNNEST(Events.tags.id))
)
)
ORDER BY
predictedgoalProb
"

# Completion message
echo "Lab successfully completed!!" 

