# FootyIQ

A first-person football decision trainer built in Godot 4.

## Run the game

```bash
godot --path .
```

## Run the tests

```bash
godot --headless --path . -s tests/run_tests.gd
```

The runner exits with a non-zero code if any test fails. The bot-vs-bot checks play 60 two-minute matches, so the full suite takes about five minutes.

## Headless bot-vs-bot matches

```bash
godot --headless --path . -s tools/headless_match.gd -- --matches 20 --seed 1 --home hard --away easy
```

| Option | Default | Meaning |
|---|---|---|
| `--matches N` | 1 | Number of matches; match *i* uses seed `S + i` |
| `--seed S` | 1 | First seed |
| `--home`, `--away` | `medium` | Difficulty from `config/difficulty.json`: `easy`, `medium`, `hard` |
| `--exploit` | none | Replace the home team's carrier with a scripted trick: `always_back` (always pass to the deepest teammate) or `wing_dribble` (run down one wing and shoot) |

It prints one JSON line with home wins, away wins, draws, goals, completed passes per team, the home team's share of possession, and the mean distance from each outfield player to the nearest outfield teammate. Match length is `headless.match_s` in `config/tuning.json`.

## Configuration

Every tunable value is in `config/`:

- `tuning.json`: physics, movement, ball control and bot behaviour
- `difficulty.json`: bot reaction time, perception noise, speed, press radius and lane cover per difficulty
- `objectives.json`: team objectives (`keep_possession`, `build_up`, `counter_attack`, `press_high`, `mid_block`, `low_block`), each a set of utility weight multipliers, a line-height offset and a press radius scale
- `drills.json`: pitch size, teams and role positions
