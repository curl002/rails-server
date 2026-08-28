# README

Install the gems required by the project:

```
bundle install
```

Add your local PostgreSQL password:
```
POSTGRES_PASSWORD=your_postgresql_password
```

Make sure PostgreSQL is installed and running locally. The application expects a PostgreSQL user named:
```
postgres
```

From the Rails project directory, run:
```
rails db:create
```

You should see confirmation that the databases were created:
```
Created database 'website'
Created database 'game_accounts'
```

Run:
```
rails db:migrate
```

Start the Rails development server:
```
rails server
```

The API will start on:
```
http://localhost:3000
```

Open the following URL in a browser:
```
http://localhost:3000
```

You should see: 
```
API is listening
```