document.addEventListener('DOMContentLoaded', () => {
  const dataForm = document.getElementById('data-form');
  const successMessage = document.getElementById('success-message');
  const errorMessage = document.getElementById('error-message');
  const entriesTable = document.getElementById('entries-table');
  const sessionIdSpan = document.getElementById('session-id');
  const serviceSelect = document.getElementById('service');
  const protoSelect = document.getElementById('proto');
  const portInput = document.getElementById('port');
  
  // Get session ID from URL or environment
  const urlParams = new URLSearchParams(window.location.search);
  const sessionId = urlParams.get('session') || '';
  sessionIdSpan.textContent = sessionId;
  
  // Service-specific port mappings
  const servicePorts = {
    'smb': { tcp: [139, 445], udp: [137, 138] },
    'snmp': { udp: [161] },
    'tftp': { udp: [69] },
    'imap': { tcp: [143], tls: [993] },
    'pop': { tcp: [110], tls: [995] },
    'ssh': { tcp: [22] },
    'ftp': { tcp: [21], tls: [990] },
    'smtp': { tcp: [25], tls: [465] },
    'http': { tcp: [80], tls: [443] },
    'api-em': { tcp: [8080], tls: [8443] },
    'crap-em': { tcp: [9999], tls: [9443] },
    'finger-em': { tcp: [79] },
    'ftp-em': { tcp: [21], tls: [990] },
    'http-em': { tcp: [80], tls: [443] },
    'imap-em': { tcp: [143], tls: [993] },
    'irc-em': { tcp: [6667], tls: [6697] },
    'ldap-em': { tcp: [389], tls: [636] },
    'memcached-em': { tcp: [11211] },
    'nntp-em': { tcp: [119], tls: [563] },
    'pop3-em': { tcp: [110], tls: [995] },
    'redis-em': { tcp: [6379], tls: [6380] },
    'smtp-em': { tcp: [25], tls: [465] },
    'snmp-em': { tcp: [161], udp: [161] },
    'socks4-em': { tcp: [1080, 1443] },
    'telnet-em': { tcp: [23], tls: [992] }
  };
  
  // Update available protocols and ports when service changes
  serviceSelect.addEventListener('change', () => {
    const service = serviceSelect.value;
    const ports = servicePorts[service] || {};
    
    // Update protocol options
    const protocols = Object.keys(ports);
    protoSelect.innerHTML = protocols.map(p => 
      `<option value="${p}">${p.toUpperCase()}</option>`
    ).join('');
    
    // Update port if needed
    updatePortOptions();
  });
  
  // Update port options when protocol changes
  protoSelect.addEventListener('change', updatePortOptions);
  
  function updatePortOptions() {
    const service = serviceSelect.value;
    const proto = protoSelect.value;
    const ports = servicePorts[service]?.[proto] || [];
    
    if (ports.length === 1) {
      portInput.value = ports[0];
    } else if (ports.length > 1) {
      portInput.value = ports[0];
    }
  }
  
  // Ensure hideMessages is called after we confirm the DOM elements exist
  if (successMessage && errorMessage) {
    hideMessages();
  }
  
  loadEntries();
  
  // Auto-append .nfr.lab to hostname
  const hostnameInput = document.getElementById('hostname');
  hostnameInput.addEventListener('input', (e) => {
    const value = e.target.value.replace(/\.nfr\.lab$/, '');
    e.target.value = value;
  });
  
  dataForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    try {
      const formData = new FormData(dataForm);
      const data = Object.fromEntries(formData.entries());
      
      // Append domain to hostname if not present
      if (!data.hostname.endsWith('.nfr.lab')) {
        data.hostname = `${data.hostname}.nfr.lab`;
      }
      
      if (!validateData(data)) {
        showError('Please fill in all required fields correctly');
        return;
      }
      
      const response = await sendData(data);
      
      if (response.success) {
        showSuccess();
        dataForm.reset();
        loadEntries();
      } else {
        showError(response.message || 'Error updating score card');
      }
    } catch (error) {
      showError('An unexpected error occurred');
      console.error('Form submission error:', error);
    }
  });
  
  async function loadEntries() {
    try {
      const response = await fetch('/cgi-bin/get_entries.cgi');
      if (!response.ok) throw new Error('Failed to load entries');
      
      const entries = await response.text();
      displayEntries(entries);
    } catch (error) {
      console.error('Failed to load entries:', error);
    }
  }
  
  function displayEntries(entriesText) {
    const entries = entriesText.split('\n')
      .filter(line => line.trim())
      .map(line => {
        const parts = line.split(' ');
        const data = {};
        parts.forEach(part => {
          const [key, value] = part.split('=');
          data[key] = value || '';
        });
        return data;
      });
    
    const table = `
      <table class="entries-table">
        <thead>
          <tr>
            <th>Service</th>
            <th>Hostname</th>
            <th>IP Address</th>
            <th>Port</th>
            <th>Protocol</th>
            <th>Flag</th>
          </tr>
        </thead>
        <tbody>
          ${entries.map(entry => `
            <tr>
              <td>${entry.service || ''}</td>
              <td>${entry.hostname || ''}</td>
              <td>${entry.target || ''}</td>
              <td>${entry.port || ''}</td>
              <td>${entry.proto || ''}</td>
              <td>${entry.flag || ''}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    `;
    
    entriesTable.innerHTML = table;
  }
  
  function validateData(data) {
    if (!data.hostname || !data.service || !data.target || !data.port || !data.proto || !data.flag) {
      return false;
    }
    
    // Validate hostname format
    if (!data.hostname.match(/^[a-zA-Z0-9-]+\.nfr\.lab$/)) {
      return false;
    }
    
    // Validate IP address format
    const ipRegex = /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
    if (!ipRegex.test(data.target)) {
      return false;
    }
    
    // Validate port number
    if (isNaN(data.port) || data.port < 1 || data.port > 65535) {
      return false;
    }
    
    // Validate flag format
    const flagRegex = /^FLAG\{[a-zA-Z0-9]+\}$/;
    if (!flagRegex.test(data.flag)) {
      return false;
    }
    
    return true;
  }
  
  async function sendData(data) {
    try {
      const response = await fetch('/cgi-bin/update.cgi', {
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
      
      return {
        success: result.includes('success'),
        message: result
      };
    } catch (error) {
      console.error('API error:', error);
      return { 
        success: false, 
        message: 'Failed to connect to the server'
      };
    }
  }
  
  function showSuccess() {
    hideMessages();
    successMessage.classList.remove('hidden');
    setTimeout(() => successMessage.classList.add('hidden'), 5000);
  }
  
  function showError(message) {
    hideMessages();
    if (message) {
      const errorText = errorMessage.querySelector('p');
      if (errorText) {
        errorText.textContent = message;
      }
    }
    errorMessage.classList.remove('hidden');
    setTimeout(() => errorMessage.classList.add('hidden'), 5000);
  }
  
  function hideMessages() {
    successMessage.classList.add('hidden');
    errorMessage.classList.add('hidden');
  }
});