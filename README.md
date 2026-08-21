# Seasons Game Mode Specs

## Game Speeds

- 1x
- 2x
- 3x

## Legendary Items

"Legendary" items carry over from season to season:

- Level 20
- Level 50
- Level 80

> **Example:** L50 would be the best item available for either:
> - Level 50
> - Level range 50-60 (TBD)

Levels open up gradually. Consumables give an initial short-term boost, declining gradually:

- Levels 1 to 20
- Levels 21 to 50
- Levels 51 to 80

---

# Consumables / Purchase Flow

## Database Structure

- `website`
- `world_1`
- `world_2`

## Purchase

1. **Browser:** User logs in.
2. **Rails:** Returns authentication token.
3. **Browser:** User enters payment details and presses **Purchase**.
4. **Rails:** Processes purchase.
5. **Rails:** Success response triggers a method to add item IDs to the `User` table.

```ruby
User.process_purchase(item_id)
```

This runs on the Rails server and triggers several database updates.

---

# Purchase Validation / Database Separation

Purchase validation will use three types of databases.

## `website`

> Godot has **no access**.

Possible tables/data:

- `users`
- `purchases`
- `subscriptions`
- `square_tokens`
- ...

## `game_accounts`

> Godot has **read-only access**.

Possible tables/data:

- `users` (?)
- `entitlements`
- `bans`
- ...

## `world`

Possible tables/data:

- `characters`
- `inventories`
- `quests`
- ...

## Access Rules

Rails has access to:

- `website`
- `game_accounts`
- `world`

Godot has:

- **Write access** to `world`
- **Read access** to `game_accounts`
- **No access at all** to `website`

## Successful Purchase Flow

```text
Square
  ↓
Rails
  ↓
Updates website.purchases
  ↓
Updates game_accounts.entitlements
  ↓
Updates world.characters
  ↓
Sends HTTP request to Godot server for toasts
```

### Reason

User registration, payments, etc. should go through the website for security. Godot's access to this information should be read-only.

Permissions are set at the database level. The `postgres_db.cpp` extension has only four registered methods:

```cpp
register_method("open", &PostgresDB::open);
register_method("close", &PostgresDB::close);
register_method("is_connected", &PostgresDB::is_connected);
register_method("query", &PostgresDB::query);
```

### Session / Login Query Note

Since Godot has read access to `game_accounts.users`, the users table should hold the session token too.

Create a separate query loop for user data in the extension:

```text
query session token first
if wrong:
    return

if no token:
    check username/password first
    if wrong:
        return
```

---

# Duplicate User Data and Publish/Subscribe

## Problem

There is a duplicate users table in both the `website` and `game_accounts` databases.

## Solution

The server needs quick access to some user information, such as:

- "Legendary" weapons
- Subscriptions
- Other relevant account data

It therefore cannot rely on the Rails server for every lookup. The Rails server also needs this information to display it on the website.

There most likely is no way of implementing this without duplicating at least some of the user information.

## Enter: Publish / Subscribe

> If the information is needed in both systems, PostgreSQL supports this through publish/subscribe.

## Simple Schema

```text
website
├── users
├── purchases
├── subscription_ids
├── item_ids
└── square_tokens
    ...

game_inventory_cache    ← read-only mirror
├── user_id             ← user ID in website
├── subscription_ids
└── item_ids

world
├── user_id
├── inventory
├── position
└── quest_stages
```

---

# PostgreSQL Publish / Subscribe

## Question

How can we create the mirror with pub/sub?

## 1. Create the Source Table

In `website`, create an `accounts` table and populate it with a test user.

```sql
CREATE TABLE accounts (
    user_id BIGINT PRIMARY KEY,
    item_ids BIGINT[],
    subscription_ids BIGINT[]
);
```

```sql
INSERT INTO accounts (
    user_id,
    item_ids,
    subscription_ids
)
VALUES (
    1001,
    ARRAY[10, 20, 30],
    ARRAY[5, 6]
);
```

## 2. Create a Replication User / Role

```sql
CREATE ROLE game_replication
WITH LOGIN REPLICATION PASSWORD 'some_password';
```

This creates a PostgreSQL user/role named `game_replication`.

- `CREATE ROLE game_replication` creates a PostgreSQL user/role named `game_replication`.
- `LOGIN` allows that role to connect to PostgreSQL.
- `REPLICATION` grants permission to establish PostgreSQL replication connections.
- `PASSWORD 'some_password'` sets the password.

## 3. Grant Read Permissions

```sql
GRANT CONNECT ON DATABASE website TO game_replication;
GRANT USAGE ON SCHEMA public TO game_replication;
GRANT SELECT ON TABLE accounts TO game_replication;
```

## 4. Create the Publication

```sql
CREATE PUBLICATION game_accounts_pub
FOR TABLE accounts (
    user_id,
    item_ids,
    subscription_ids
);
```

## 5. Create the Mirror Table

In the `game_accounts` database, create the table containing the data that will be published:

```sql
CREATE TABLE accounts (
    user_id BIGINT PRIMARY KEY,
    item_ids BIGINT[],
    subscription_ids BIGINT[]
);
```

## 6. Create the Subscription

```sql
CREATE SUBSCRIPTION website_accounts_sub
CONNECTION 'host=10.0.0.10 port=5432 dbname=website user=game_replication password=some_password'
PUBLICATION game_accounts_pub;
```

At this point, changes made to the `accounts` table in the original database should be reflected in the subscribed table.

> **Note:** PostgreSQL supports concurrency and locks, so a pub/sub should not interfere with concurrent access.

---

# Rails - Config & First Migration

The same pattern can be achieved with Rails through migration files.

## `config/database.yml`

```yaml
development:
  primary:
    adapter: postgresql
    database: website
    username: postgres
    password: your_password
    host: localhost

  game_accounts:
    adapter: postgresql
    database: game_accounts
    username: postgres
    password: your_password
    host: localhost
    migrations_paths: db/game_accounts_migrate
```

## Website / Primary Database

Generate the migration:

```bash
bin/rails generate migration CreateAccounts
```

Migration:

```ruby
class CreateAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :accounts, id: false do |t|
      t.bigint :user_id, null: false, primary_key: true
      t.bigint :item_ids, array: true, default: []
      t.bigint :subscription_ids, array: true, default: []

      # other columns 1
      # other columns 2
      # other columns 3
    end
  end
end
```

Run:

```bash
bin/rails db:migrate
```

This creates the `accounts` table which will later be subscribed to.

---

# Rails - Publication Pattern

Create the publication migration file:

```bash
bin/rails generate migration CreateGameReplicationPublication
```

The document's migration uses SQL through `execute` to create the PostgreSQL database role, permissions, and publication:

```ruby
class CreateGameReplicationPublication < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      CREATE ROLE game_replication
      WITH LOGIN REPLICATION PASSWORD 'some_password';
    SQL

    execute <<~SQL
      GRANT CONNECT ON DATABASE website TO game_replication;
    SQL

    execute <<~SQL
      GRANT USAGE ON SCHEMA public TO game_replication;
    SQL

    execute <<~SQL
      GRANT SELECT ON TABLE accounts TO game_replication;
    SQL

    execute <<~SQL
      CREATE PUBLICATION website_to_game_pub
      FOR TABLE accounts (
        user_id,
        item_ids,
        subscription_ids
      );
    SQL
  end

  def down
    execute "DROP PUBLICATION IF EXISTS website_to_game_pub;"
    execute "DROP ROLE IF EXISTS game_replication;"
  end
end
```

> **Note:** The document states that Rolify creates application-level roles, but not native PostgreSQL server database roles created through `CREATE ROLE`.

---

# Rails - Mirror Database

For the `game_accounts` mirror database, specify the database when creating the migration:

```bash
bin/rails generate migration CreateAccounts --database game_accounts
```

Migration:

```ruby
class CreateAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :accounts, id: false do |t|
      t.bigint :user_id, null: false, primary_key: true
      t.bigint :item_ids, array: true, default: []
      t.bigint :subscription_ids, array: true, default: []
    end
  end
end
```

Run:

```bash
bin/rails db:migrate:game_accounts
```

> **Note:** The document describes this as the correct way to run the migration because Rails resolves which database `game_accounts` belongs to based on the database configuration.

---

# Rails - Subscription Pattern

Create the subscription migration file:

```bash
bin/rails generate migration CreateWebsiteSubscription
```

SQL commands for the subscription pattern:

```ruby
class CreateWebsiteSubscription < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL
      CREATE SUBSCRIPTION website_accounts_sub
      CONNECTION 'host=10.0.0.10 port=5432 dbname=website user=game_replication password=some_password'
      PUBLICATION website_to_game_pub;
    SQL
  end
end
```
