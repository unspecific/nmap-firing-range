/**
 * Utility functions for data handling and validation
 */

/**
 * Format a timestamp to a human-readable date and time
 * @param {string} timestamp - ISO format timestamp
 * @returns {string} - Formatted date and time
 */
function formatDateTime(timestamp) {
  if (!timestamp) return '';
  
  const date = new Date(timestamp);
  
  // Check if date is valid
  if (isNaN(date.getTime())) {
    return timestamp; // Return original if invalid
  }
  
  // Format options
  const options = {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  };
  
  return date.toLocaleDateString(undefined, options);
}

/**
 * Sanitize a string to prevent XSS
 * @param {string} str - Input string
 * @returns {string} - Sanitized string
 */
function sanitizeString(str) {
  if (!str) return '';
  
  // Create a temporary element
  const temp = document.createElement('div');
  
  // Set the content as text (which escapes HTML)
  temp.textContent = str;
  
  // Return the sanitized content
  return temp.innerHTML;
}

/**
 * Debounce function to limit how often a function can be called
 * @param {Function} func - Function to debounce
 * @param {number} wait - Milliseconds to wait
 * @returns {Function} - Debounced function
 */
function debounce(func, wait = 300) {
  let timeout;
  
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

/**
 * Generate a unique ID
 * @returns {string} - Unique ID
 */
function generateId() {
  return Math.random().toString(36).substring(2) + Date.now().toString(36);
}

// Export utilities for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    formatDateTime,
    sanitizeString,
    debounce,
    generateId
  };
}