Automated Moodle for CapRover

This repository contains a robust and automated implementation of Moodle (LMS), specifically optimized for deployment via CapRover.

Unlike official images, this version functions as a "Deployment Manager": it downloads Moodle core, installs plugins via Git, dynamically configures config.php based on environment variables, and manages Nginx/PHP-FPM/Cron within a single container.

🚀 Features

Zero-Touch Config: config.php is automatically generated from CapRover environment variables.

Plugin Manager: Automatically installs and updates plugins via JSON (supports specific Branches).

Auto-Update: On container restart, it checks for core and plugin updates via Git.

Full Stack: Single container running Nginx (Web Server), PHP-FPM, and Cron (via Supervisor).

Advanced Customization: Allows injection of raw PHP configurations (MOODLE_EXTRA_PHP) directly from the CapRover dashboard.

🛠️ How to Deploy on CapRover

Prerequisites

A running CapRover server.

A database created (PostgreSQL or MySQL/MariaDB) in CapRover (e.g., PostgreSQL One-Click App).

Step-by-Step

Create a new App in CapRover (e.g., mymoodle).

Go to the Deployment tab.

Under "Method 3: Deploy from Github/Bitbucket/Gitlab", enter the URL of this repository:

https://github.com/EsdrasCaleb/moodle_sentry_app

Branch: main (or the branch you are using).

Click Save & Update.

Note: The initial deploy will fail or keep restarting. This is normal because the database credentials have not been configured yet.

Go to the App Configs tab. Thanks to captain-definition, all necessary variables will already be listed there. Fill in the values:

| Variable | Description | Example |
| MOODLE_URL | Critical: The public URL of your app. | https://mymoodle.yourdomain.com |
| DB_HOST | Name of the database container in CapRover. | srv-captain--my-postgres |
| DB_NAME | Database name. | moodle |
| DB_USER | Database user. | postgres |
| DB_PASS | Database password. | mypassword123 |
| DB_TYPE | Database type. | pgsql (or mysqli) |

Click Save & Update. The container will restart, install Moodle, and become available.

🧩 Plugin Management (JSON)

You can automatically install plugins by defining the MOODLE_PLUGINS_JSON environment variable in CapRover or by creating a plugins.json file in the repository root (if using a private fork).

JSON Format

It must be a list of objects containing giturl and installpath. Optionally, it can contain branch.
```
[
{
"giturl": "[https://github.com/moodle/moodle-mod_hvp.git](https://github.com/moodle/moodle-mod_hvp.git)",
"branch": "stable",
"installpath": "mod/hvp"
},
{
"giturl": "[https://github.com/ethiz/moodle-theme_moove.git](https://github.com/ethiz/moodle-theme_moove.git)",
"installpath": "theme/moove"
}
]
```


Behavior:

If the directory does not exist: Performs git clone.

If the directory exists: Performs git pull (and checkout if a branch is defined).

After downloading, the script automatically runs Moodle's upgrade.php.

⚙️ Advanced Configuration (config.php)

It is not necessary (nor possible) to edit the config.php file manually, as it is recreated on every boot. To add custom configurations (such as reverse proxy, debug, or Redis settings), use the MOODLE_EXTRA_PHP variable.

Usage Example in CapRover:

Variable: MOODLE_EXTRA_PHP
Value:
```
$CFG->sslproxy = 1;
$CFG->reverseproxy = 1;
// $CFG->debug = 32767; $CFG->debugdisplay = 1;
```


The script will inject this code directly into config.php before setup.

💾 Data Persistence

The captain-definition automatically configures a persistent volume for the Moodle data directory.

Internal Path: /var/www/moodledata

Docker Volume: moodle-data-persistence

Warning: The Moodle source code (/var/www/html) is NOT persistent by default. This is intentional to allow version updates by simply changing the Docker tag or the MOODLE_VERSION variable. If you edit core files manually inside the container, you will lose changes on the next deploy.

⚠️ Troubleshooting

1. "Redirect Loop" error or HTTPS issues:
   CapRover handles SSL Termination. Moodle needs to know it is running under HTTPS. Add the following to the MOODLE_EXTRA_PHP variable:
```
$CFG->sslproxy = 1;
```


2. Is the installation taking too long?
   Yes. On the first boot, the container downloads ~500MB from GitHub (Moodle Core) + Plugins. It can take 2 to 5 minutes. Check the logs in CapRover ("Deployment Logs" or "App Logs").

3. Changing PHP version:
   The PHP version is defined in the Dockerfile (Build Time). To change it (e.g., from 8.1 to 8.2), edit captain-definition changing PHP_VERSION and trigger a new deploy (Force Build).