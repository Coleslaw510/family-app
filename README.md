# Family App

A private iOS app for Cole and his wife, plus the small server that holds the family data. The interface follows system appearance and has seven tabs: Home, Budget, Marriage, Family, Food, Calendar, and Vacations. The native tab bar places overflow destinations in Apple's More screen.

The phone app is SwiftUI. SpriteKit plays confetti when a weekly check-in is saved or a trip fund hits its goal, and a quiet sparkle sits behind the vacation countdown. The server is FastAPI and SQLite. Only people in the family can read or write that family's data.

Default server address, already filled in on the first screen:

`https://132-145-159-218.sslip.io`

## iOS app

Requirements: iOS 16 or later, iPhone.

Open the project locally:

```bash
brew install xcodegen
cd ios
xcodegen generate
open FamilyApp.xcodeproj
```

Bundle id: `com.colemcclintock.familyapp`.

Sign it with your own Apple Development team and run it on a phone. The committed project does not include a signing team. The GitHub workflow builds an **unsigned** `.ipa` (`CODE_SIGNING_ALLOWED=NO`) and uploads it as a workflow artifact. Pushing a tag named `v*` also attaches that IPA to a GitHub Release.

Re-sign an artifact before installing:

```bash
unzip -q FamilyApp-unsigned.ipa -d unsigned
codesign -f -s "Apple Development: Your Name (TEAMID)" unsigned/Payload/FamilyApp.app
rm -f FamilyApp.ipa
(cd unsigned && zip -qry ../FamilyApp.ipa Payload)
```

Sideloadly, Apple Configurator, or Xcode's Devices window can install the re-signed IPA.

On first launch, confirm the server URL, enter your name, then either **Create family** or **Join with a code**. Creating a family shows a 6-character code. It expires in 24 hours and works once. The session token is stored in the Keychain.

Changing the server in Settings signs you out, because the token belongs to that server.

## Server

Config is environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` | `8000` | HTTP port |
| `DB_PATH` | `server/data/family.db` | SQLite file |
| `JOIN_CODE_TTL_HOURS` | `24` | How long a join code lasts |
| `JOIN_MAX_ATTEMPTS` | `8` | Failed joins per IP per window |
| `JOIN_WINDOW_SECONDS` | `900` | Join rate-limit window |
| `CREATE_MAX_ATTEMPTS` | `8` | New families per IP per window |
| `CREATE_WINDOW_SECONDS` | `3600` | Create-family window |
| `SESSION_DAYS` | `400` | Bearer token lifetime |

Amounts are integer cents. Dates are `YYYY-MM-DD`. Times are `YYYY-MM-DDTHH:MM:SS` in the household's local clock, stored as text and shown back the same way.

### Docker Compose (ARM or x86)

On the Ubuntu VM:

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
git clone https://github.com/Coleslaw510/family-app.git
cd family-app
sudo docker compose up -d --build
```

- App API: `http://<vm>:8000` (handy while checking; the phone should use HTTPS)
- Public HTTPS: `https://132-145-159-218.sslip.io` via Caddy in the same compose file
- Health: `https://132-145-159-218.sslip.io/health`
- Interactive docs: `https://132-145-159-218.sslip.io/docs`

sslip.io turns the VM's public IP `132.145.159.218` into that hostname, so Caddy can get a certificate without a separate DNS host. Ports **80** and **443** must be open in the Oracle security list **and** in the VM firewall. Oracle's Ubuntu images often drop new ports in iptables even after the security list allows them:

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8000 -j ACCEPT
sudo netfilter-persistent save
```

The SQLite file lives in the `family-data` volume at `/data/family.db` inside the app container.

### systemd, without Docker

```bash
sudo apt-get install -y python3 python3-venv caddy
sudo mkdir -p /opt/family-app /var/lib/family-app
sudo cp -a server /opt/family-app/server
sudo cp deploy/family-app.service /etc/systemd/system/family-app.service
sudo cp deploy/Caddyfile /etc/caddy/Caddyfile
cd /opt/family-app/server
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
sudo systemctl daemon-reload
sudo systemctl enable --now family-app caddy
```

`deploy/family-app.service` listens on `127.0.0.1:8000`. Caddy terminates HTTPS and proxies to it.

### Tests

```bash
cd server
python3 -m pip install -r requirements.txt -r requirements-dev.txt
python3 -m pytest -q
```

`server/examples/sample-2026.csv` is a tiny file you can import from the Budget tab to try **Suggest budgets**.

## What each tab stores

- **Home** reads one dashboard: this month's pace, the latest expenses, the next date, anniversary countdown, a few chores, upcoming events, and the next trip.
- **Budget** is per month. Category envelopes (with a default that later months inherit), transactions, expected income (planned vs received), bills, manual account balances, a year chart, CSV import, and suggested budgets from earlier months. Marking a bill paid posts an expense. A monthly bill then rolls forward.
- **Marriage** holds the anniversary, the first-date anniversary, birthdays, date nights, a shared weekly check-in, and love notes. Flower logs and the "it's been a while" nudge belong to the person who logged them. The other person does not see them.
- **Family** is chores (with an assignee), a grocery list, shared notes, and important dates.
- **Calendar** is shared events in a month grid and a day agenda.
- **Vacations** are trips with dates, a savings goal, a packing list, and itinerary notes.

The app refreshes when you pull down, and again about every 45 seconds.

## API

Send `Authorization: Bearer <token>` except on health, create, and join. A wrong family id is a 404, not someone else's row.

| Method | Path | What it does |
| --- | --- | --- |
| GET | `/health` | `{ok, version}` |
| POST | `/v1/families` | Create a family. Body: `name`, optional `family_name`. Returns token, join code, family, member |
| POST | `/v1/families/join` | Body: `code`, `name` |
| POST | `/v1/logout` | Drops this token |
| GET, PATCH | `/v1/me` | Profile. PATCH body: `name` |
| PATCH | `/v1/family` | Rename the household |
| POST | `/v1/join-codes` | Another single-use code |
| GET | `/v1/dashboard?today=YYYY-MM-DD` | Home payload. Pass the phone's date |
| GET | `/v1/budget?month=YYYY-MM&today=YYYY-MM-DD` | Full budget screen |
| POST | `/v1/budget/suggest` | `{month, apply, today}` averages earlier months into budgets |
| GET, POST | `/v1/categories` | List or add |
| PATCH, DELETE | `/v1/categories/{id}` | Edit or remove |
| PUT | `/v1/categories/{id}/budget` | `{month, amount_cents, set_default}` |
| GET, POST | `/v1/transactions` | List (`month` optional) or add |
| PATCH, DELETE | `/v1/transactions/{id}` | Edit or remove. `member_id` stays the person who added it |
| POST | `/v1/transactions/import` | `{rows: [{date, merchant, amount_cents, category?, kind?}]}`. Duplicates of the same import row are skipped |
| GET, POST | `/v1/income` | Expected income entries |
| PATCH, DELETE | `/v1/income/{id}` | |
| GET, POST | `/v1/bills` | |
| PATCH, DELETE | `/v1/bills/{id}` | `paid: true` posts an expense and advances monthly bills |
| GET, POST | `/v1/accounts` | Manual balances, including a negative credit card |
| PATCH, DELETE | `/v1/accounts/{id}` | |
| GET, PUT | `/v1/marriage` | Anniversary, first date, flower nudge days |
| POST, PATCH, DELETE | `/v1/birthdays` | |
| POST, DELETE | `/v1/flowers` | Only the caller sees and deletes their logs |
| POST, PATCH, DELETE | `/v1/dates` | Date nights |
| POST, DELETE | `/v1/checkins` | Weekly answers. Both partners can read the history. `week_start` is a Monday |
| POST, DELETE | `/v1/love-notes` | Author can delete |
| GET | `/v1/household` | Chores, grocery, notes, important dates |
| POST, PATCH, DELETE | `/v1/chores` | |
| POST, PATCH, DELETE | `/v1/important-dates` | |
| POST, PATCH, DELETE | `/v1/notes` | `kind` is `note` or `grocery` |
| GET, POST | `/v1/events` | Optional `start` and `end` |
| PATCH, DELETE | `/v1/events/{id}` | |
| GET, POST | `/v1/trips` | Includes packing and itinerary |
| PATCH, DELETE | `/v1/trips/{id}` | Patch reports `goal_just_reached` when savings cross the goal |
| POST | `/v1/trips/{id}/packing` | |
| PATCH, DELETE | `/v1/packing/{id}` | |
| POST | `/v1/trips/{id}/itinerary` | |
| PATCH, DELETE | `/v1/itinerary/{id}` | |

Join codes are stored as SHA-256 hashes. Failed join attempts are rate-limited per IP. Creating families is rate-limited too, since this server sits on a public hostname.

Pace is `on_pace`, `watch`, `over`, or `no_budget`. Safe-to-spend is what's left after upcoming unpaid bills this month, divided by the days left. Insights are rules (over budget, a bill due soon, a category running under its older average). They are not a model.

## Version 1.2

Presentation-only refresh of the iOS app: native system tab navigation, adaptive grouped glass/material cards, capsule and tinted icon buttons, a native grouped Settings form, and tappable Home section headers. Liquid Glass effects are used on iOS 26 and newer; earlier supported iOS versions retain system-material and native button fallbacks. No server, data, or domain feature changes.

## Version 1.1

Additive only. Existing families, events, and trips stay in the SQLite file. New tables are created beside them; nothing is dropped.

Server environment (never commit the values):

| Variable | Purpose |
| --- | --- |
| `GEMINI_API_KEY` | Budget questions and meal estimates. Server only. |
| `GEMINI_MODEL` | Optional. Defaults to `gemini-3.1-flash-lite`. |
| `RENTCAST_API_KEY` | Optional monthly home-value lookup. If the key is missing or RentCast rejects it, the app stays quiet. |
| `FEED_POLL_SECONDS` | How often iCal feeds are fetched. Default 900. |
| `FAMILY_APP_SECRETS` | Optional path to the secrets file. Compose defaults to `/home/ubuntu/.config/family-app/secrets.env`. |

Put the keys in `/home/ubuntu/.config/family-app/secrets.env` (mode 600). Compose loads that file with `required: false`, so a missing file does not stop the stack.

```bash
git pull
docker compose up -d --build
```

Calendar feed addresses are stored on the server and only a masked host is sent back to the phone. They are not written to logs.

## Not in 1.1

- SimpleFIN bank sync. Import a CSV or Excel export instead.
- Google Calendar two-way sync. Read-only iCal feeds are in 1.1.

## Design notes that aren't on the mockups

- A new family starts with eight categories (Groceries, Dining, Fuel, Bills / Utilities, Kids / Family, Date Night, Shopping, Vacation fund) and zero budgets, so the app doesn't pretend November already has a $4,800 plan.
- The home screen's three amounts are the latest expenses, labeled by category, matching the mockup.
- Flower reminders are personal. Check-ins, love notes, chores, money, events, and trips are shared.
- CSV import accepts `yyyy-MM-dd` and `M/d/yyyy`. Map the columns if the header isn't obvious. Turn on "flip signs" when the bank uses negatives for spending.
- Suggest budgets averages each category across earlier months that contain any spending, including zeros for categories that were quiet, then rounds to the nearest dollar. It writes that month and sets the usual monthly budget.
