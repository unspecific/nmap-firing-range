# Simple Data Collection System

A lightweight web application designed to run on Alpine Linux using thttpd server. This application collects data via a simple form interface and saves it to a local file on the container.

## Features

- Minimalist, resource-efficient web interface
- Form for submitting data to update a local file
- Client-side data validation
- Simple CGI script for server-side processing
- Responsive design that works on all devices

## Requirements

- Alpine Linux
- thttpd web server
- Write access to the data directory

## Installation

1. Copy all files to your web root directory
2. Make the CGI script executable:
   ```
   chmod +x cgi-bin/update.cgi
   ```
3. Ensure the data directory is writable:
   ```
   mkdir -p /var/data
   chmod 755 /var/data
   ```

## Usage

1. Access the web interface through your browser
2. Fill out the form with your data
3. Submit the form to save data to the local file

## File Structure

- `index.html` - Main webpage with the data input form
- `css/` - Style sheets for the application
  - `normalize.css` - CSS reset for consistent styling
  - `styles.css` - Main application styles
- `js/` - JavaScript files
  - `app.js` - Main application logic
  - `utils.js` - Utility functions
  - `dataService.js` - Data handling service
- `cgi-bin/` - Server-side scripts
  - `update.cgi` - Shell script to process form data and update the local file

## Data File

Data is stored in `/var/data/collection.txt` in the following format:

```
TIMESTAMP|NAME|VALUE|CATEGORY|NOTES
2025-01-01 12:00:00|Sample Name|100|general|Sample notes
```

## Customization

- Edit `styles.css` to change the appearance
- Modify `cgi-bin/update.cgi` to change how data is processed and stored
- Extend functionality by adding new fields to the form in `index.html`