/**
 * Data Service
 * Handles data operations and persistence
 */

/**
 * Data Service class
 */
class DataService {
  /**
   * Create a new DataService instance
   */
  constructor() {
    this.endpoint = '/cgi-bin/update.cgi';
  }
  
  /**
   * Submit data to the server
   * @param {Object} data - Form data to submit
   * @returns {Promise<Object>} - Response with success status and message
   */
  async submitData(data) {
    try {
      const response = await fetch(this.endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams(data),
      });
      
      if (!response.ok) {
        throw new Error(`Server responded with status: ${response.status}`);
      }
      
      const result = await response.text();
      
      if (result.includes('success')) {
        return { 
          success: true,
          message: 'Data submitted successfully'
        };
      } else {
        return { 
          success: false, 
          message: result || 'Error submitting data' 
        };
      }
    } catch (error) {
      console.error('API error:', error);
      return { 
        success: false, 
        message: 'Failed to connect to the server' 
      };
    }
  }
  
  /**
   * Validate form data before submission
   * @param {Object} data - Form data to validate
   * @returns {Object} - Validation result with isValid flag and errors
   */
  validateData(data) {
    const errors = {};
    
    // Validate name
    if (!data.name || data.name.trim() === '') {
      errors.name = 'Name is required';
    }
    
    // Validate value
    if (!data.value) {
      errors.value = 'Value is required';
    } else if (isNaN(data.value) || Number(data.value) < 0) {
      errors.value = 'Value must be a positive number';
    }
    
    // Check if there are any errors
    const isValid = Object.keys(errors).length === 0;
    
    return {
      isValid,
      errors
    };
  }
}

// Create a singleton instance
const dataService = new DataService();

// Export the instance for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = dataService;
}