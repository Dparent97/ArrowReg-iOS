// Helper functions for citation extraction and eCFR link generation

/**
 * Extract CFR information from filename or text
 * @param {string} text - The text to extract from
 * @returns {Object|null} - CFR info or null
 */
function extractCFRInfo(text) {
  // Try to match various CFR patterns
  const patterns = [
    /(?:title[- ]?)?(\d+)[- ]?CFR[- ]?(?:part[- ]?)?(\d+)(?:\.(\d+))?/i,
    /ECFR[- ]?title(\d+)/i,
    /46[- ]?CFR[- ]?(\d+)(?:\.(\d+))?/i,  // Common pattern for Title 46
    /33[- ]?CFR[- ]?(\d+)(?:\.(\d+))?/i,  // Common pattern for Title 33
  ];
  
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      // Handle different match groups based on pattern
      if (pattern.source.includes('46') || pattern.source.includes('33')) {
        const title = pattern.source.includes('46') ? '46' : '33';
        return {
          title: title,
          part: match[1],
          section: match[2] || null
        };
      } else {
        return {
          title: match[1],
          part: match[2] || null,
          section: match[3] || null
        };
      }
    }
  }
  
  return null;
}

/**
 * Generate eCFR URL from CFR information
 * @param {Object} cfrInfo - CFR information object
 * @returns {string} - eCFR URL
 */
function generateECFRUrl(cfrInfo) {
  if (!cfrInfo || !cfrInfo.title) return null;
  
  const baseUrl = `https://www.ecfr.gov/current/title-${cfrInfo.title}`;
  
  if (cfrInfo.section && cfrInfo.part) {
    // Direct link to specific section
    return `${baseUrl}/section-${cfrInfo.part}.${cfrInfo.section}`;
  } else if (cfrInfo.part) {
    // Link to part
    return `${baseUrl}/part-${cfrInfo.part}`;
  } else {
    // Link to title
    return baseUrl;
  }
}

/**
 * Process file citation and generate appropriate citation object
 * @param {Object} fileCitation - OpenAI file citation object
 * @param {Object} fileDetails - File details from OpenAI
 * @returns {Object} - Processed citation object
 */
function processFileCitation(fileCitation, fileDetails) {
  const fileName = fileDetails.filename || fileCitation.file_id;
  const fileId = fileCitation.file_id;
  
  // Extract CFR information from filename
  const cfrInfo = extractCFRInfo(fileName);
  
  // Determine source type
  let source = 'document';
  let title = fileName;
  let url = null;
  
  if (cfrInfo) {
    // It's a CFR document
    source = `cfr${cfrInfo.title}`;
    title = `${cfrInfo.title} CFR`;
    if (cfrInfo.part) {
      title += ` Part ${cfrInfo.part}`;
    }
    if (cfrInfo.section) {
      title += ` § ${cfrInfo.section}`;
    }
    url = generateECFRUrl(cfrInfo);
  } else if (fileName.toLowerCase().includes('abs')) {
    source = 'abs';
    title = 'ABS Rules';
  } else if (fileName.toLowerCase().includes('nvic')) {
    source = 'nvic';
    title = 'NVIC Guidelines';
  }
  
  // Extract quoted text if available
  let quotedText = fileCitation.quote || '';
  if (quotedText) {
    // Try to extract CFR reference from quoted text as well
    const quoteCFR = extractCFRInfo(quotedText);
    if (quoteCFR && !url) {
      url = generateECFRUrl(quoteCFR);
    }
    
    // Truncate long quotes
    if (quotedText.length > 200) {
      quotedText = quotedText.substring(0, 197) + '...';
    }
  }
  
  return {
    id: `file-${fileId}`,
    title: title,
    section: quotedText || 'Referenced content',
    source: source,
    url: url,
    filename: fileName,
    fileId: fileId,
    relevanceScore: 0.95
  };
}

/**
 * Process text annotations and replace with citation markers
 * @param {string} text - The text with annotations
 * @param {Array} annotations - OpenAI annotations array
 * @param {Array} citations - Citations array to append to
 * @param {Set} seen - Set of seen citation IDs
 * @param {Object} env - Environment variables
 * @returns {Object} - Processed text and citations
 */
async function processAnnotations(text, annotations, citations, seen, env) {
  let processedText = text;
  const replacements = [];
  
  // Sort annotations by start_index in reverse order to process from end to start
  const sortedAnnotations = [...annotations].sort((a, b) => b.start_index - a.start_index);
  
  for (const annotation of sortedAnnotations) {
    if (annotation.type === 'file_citation') {
      const fileCitation = annotation.file_citation;
      const fileId = fileCitation.file_id;
      const citationId = `file-${fileId}`;
      
      if (!seen.has(citationId)) {
        seen.add(citationId);
        
        try {
          // Get file details from OpenAI
          const fileResponse = await fetch(`https://api.openai.com/v1/files/${fileId}`, {
            headers: {
              'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
              'OpenAI-Beta': 'assistants=v2'
            }
          });
          
          if (fileResponse.ok) {
            const fileDetails = await fileResponse.json();
            const citation = processFileCitation(fileCitation, fileDetails);
            citations.push(citation);
            
            // Replace annotation text with citation marker
            const citationMarker = `[${citations.length}]`;
            const startIndex = annotation.start_index;
            const endIndex = annotation.end_index;
            
            // Store replacement for later processing
            replacements.push({
              start: startIndex,
              end: endIndex,
              marker: citationMarker
            });
          }
        } catch (error) {
          console.error('Error fetching file details:', error);
        }
      }
    }
  }
  
  // Apply replacements from end to start
  for (const replacement of replacements) {
    processedText = processedText.slice(0, replacement.start) + 
                   replacement.marker + 
                   processedText.slice(replacement.end);
  }
  
  return { text: processedText, citations };
}

/**
 * Extract CFR citations from text (fallback method)
 * @param {string} text - The text to extract from
 * @param {Array} citations - Citations array to append to
 * @param {Set} seen - Set of seen citation IDs
 */
function extractCFRCitations(text, citations, seen) {
  const cfrRegex = /(\d+)\s*CFR\s*(?:Part\s*)?(\d+)(?:\.(\d+))?/gi;
  let match;
  
  while ((match = cfrRegex.exec(text)) !== null) {
    const titleNum = match[1];
    const partNum = match[2];
    const sectionNum = match[3] || null;
    
    const cfrInfo = {
      title: titleNum,
      part: partNum,
      section: sectionNum
    };
    
    const id = sectionNum ? `cfr-${titleNum}-${partNum}.${sectionNum}` : `cfr-${titleNum}-${partNum}`;
    
    if (!seen.has(id)) {
      seen.add(id);
      
      const url = generateECFRUrl(cfrInfo);
      const sectionText = sectionNum ? 
        `${titleNum} CFR § ${partNum}.${sectionNum}` : 
        `${titleNum} CFR Part ${partNum}`;
      
      citations.push({
        id,
        source: 'eCFR',
        section: sectionText,
        title: `Title ${titleNum} CFR`,
        url: url,
        relevanceScore: 0.8
      });
    }
  }
}

export {
  extractCFRInfo,
  generateECFRUrl,
  processFileCitation,
  processAnnotations,
  extractCFRCitations
};
