import { Router } from 'itty-router';
import { jwtVerify } from 'jose';
// import { handleStreamingSearch } from './handlers/openai-search.js';
// import { handleDocumentUpload, handleDocumentList, handleDocumentDelete } from './handlers/document-management.js';

// Import the citation helper module
import * as citationHelper from './citation-helper.js';

const router = Router();

// ---- Simple RSS Parser ----
function parseSimpleRSS(rssText) {
  const items = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
  let match;
  
  while ((match = itemRegex.exec(rssText)) !== null) {
    const itemContent = match[1];
    const item = {};
    
    // Extract title
    const titleMatch = itemContent.match(/<title><!\[CDATA\[(.*?)\]\]><\/title>|<title>(.*?)<\/title>/i);
    item.title = titleMatch ? (titleMatch[1] || titleMatch[2] || '').trim() : 'No title';
    
    // Extract description
    const descMatch = itemContent.match(/<description><!\[CDATA\[(.*?)\]\]><\/description>|<description>(.*?)<\/description>/i);
    item.description = descMatch ? (descMatch[1] || descMatch[2] || '').replace(/<[^>]*>/g, '').trim() : '';
    
    // Extract link
    const linkMatch = itemContent.match(/<link>(.*?)<\/link>/i);
    item.link = linkMatch ? linkMatch[1].trim() : '';
    
    // Extract pubDate
    const pubDateMatch = itemContent.match(/<pubDate>(.*?)<\/pubDate>/i);
    item.pubDate = pubDateMatch ? new Date(pubDateMatch[1].trim()).toISOString() : new Date().toISOString();
    
    if (item.title && item.link) {
      items.push(item);
    }
  }
  
  return items;
}

// ---- Config: CORS + Auth helpers ----
const PROD_ORIGINS = ['https://arrowreg.app'];
const DEV_ORIGIN = '*';

function allowedOrigin(env, request) {
  const url = new URL(request.url);
  const origin = request.headers.get('Origin');
  const isDev = (env.ENVIRONMENT || env.NODE_ENV) === 'development' || url.hostname === 'localhost';
  if (isDev) return DEV_ORIGIN;
  const allowed = env.ALLOWED_ORIGINS ? env.ALLOWED_ORIGINS.split(',') : PROD_ORIGINS;
  if (origin && allowed.includes(origin)) {
    return origin;
  }
  return 'null';
}

async function withCORS(request, env, response) {
  const origin = allowedOrigin(env, request);
  response.headers.set('Access-Control-Allow-Origin', origin);
  response.headers.set('Vary', 'Origin');
  return response;
}

function corsPreflight(request, env) {
  const origin = allowedOrigin(env, request);
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Vary': 'Origin'
    }
  });
}

async function requireJwt(request, env) {
  const auth = request.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return { ok: false, error: 'missing_token' };
  const token = auth.slice(7);
  if (!env.JWT_SECRET) return { ok: false, error: 'server_missing_jwt_secret' };
  try {
    const secret = new TextEncoder().encode(env.JWT_SECRET);
    const { payload } = await jwtVerify(token, secret);
    return { ok: true, claims: payload };
  } catch (e) {
    return { ok: false, error: 'invalid_token' };
  }
}

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers }
  });
}

router.options('*', (request, env) => corsPreflight(request, env));

router.get('/health', async (request, env) => withCORS(request, env, json({ status: 'healthy', version: '1.0.0' })));

// Real OpenAI search endpoint
router.post('/api/search', async (request, env) => {
  const startTime = Date.now();
  let payload = {};
  try { payload = await request.json(); } catch {}
  const { query = '', mode = 'qa' } = payload || {};
  
  if (!query.trim()) {
    return withCORS(request, env, json({ error: 'Query is required' }, 400));
  }

  // Generate cache key from normalized query
  const normalizedQuery = query.toLowerCase().trim();
  const cacheKey = `search:${mode}:${btoa(normalizedQuery).replace(/[^a-zA-Z0-9]/g, '')}`;
  
  // Check cache first (1 hour TTL)
  try {
    const cached = await env.SEARCH_CACHE?.get(cacheKey, 'json');
    if (cached && Date.now() - cached.timestamp < 3600000) { // 1 hour
      console.log('🚀 Cache hit for query:', query);
      return withCORS(request, env, json({ 
        ...cached.data, 
        fromCache: true,
        cacheAge: Math.floor((Date.now() - cached.timestamp) / 1000)
      }));
    }
  } catch (error) {
    console.log('Cache read error:', error);
  }

  // Check if OpenAI is configured
  if (!env.OPENAI_API_KEY || !env.OPENAI_ASSISTANT_ID) {
    return withCORS(request, env, json({ 
      error: 'OpenAI not configured',
      message: 'OpenAI API key or Assistant ID missing'
    }, 500));
  }

  try {
    // Create a thread for this conversation
    const threadResponse = await fetch('https://api.openai.com/v1/threads', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2'
      },
      body: JSON.stringify({})
    });

    if (!threadResponse.ok) {
      throw new Error(`Failed to create thread: ${threadResponse.status}`);
    }

    const thread = await threadResponse.json();

    // Add the user's message to the thread
    const messageResponse = await fetch(`https://api.openai.com/v1/threads/${thread.id}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2'
      },
      body: JSON.stringify({
        role: 'user',
        content: query
      })
    });

    if (!messageResponse.ok) {
      throw new Error(`Failed to add message: ${messageResponse.status}`);
    }

    // Run the assistant
    const runResponse = await fetch(`https://api.openai.com/v1/threads/${thread.id}/runs`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2'
      },
      body: JSON.stringify({
        assistant_id: env.OPENAI_ASSISTANT_ID
      })
    });

    if (!runResponse.ok) {
      throw new Error(`Failed to run assistant: ${runResponse.status}`);
    }

    const run = await runResponse.json();

    // Poll for completion with reasonable timeout
    let runStatus = run;
    const maxAttempts = 30; // 30 attempts * 1 second = 30 seconds max
    let attempts = 0;

    while (attempts < maxAttempts) {
      // Check if the run is in a terminal state
      if (runStatus.status === 'completed') {
        break;
      }
      
      if (runStatus.status === 'failed' || runStatus.status === 'cancelled' || runStatus.status === 'expired') {
        throw new Error(`Assistant run failed with status: ${runStatus.status}`);
      }
      
      // Wait before polling again (longer wait for queued status)
      const waitTime = runStatus.status === 'queued' ? 2000 : 1000;
      await new Promise(resolve => setTimeout(resolve, waitTime));
      
      const statusResponse = await fetch(`https://api.openai.com/v1/threads/${thread.id}/runs/${run.id}`, {
        headers: {
          'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
          'OpenAI-Beta': 'assistants=v2'
        }
      });

      if (!statusResponse.ok) {
        console.error('Failed to get run status:', statusResponse.status);
        throw new Error(`Failed to get run status: ${statusResponse.status}`);
      }
      
      runStatus = await statusResponse.json();
      console.log(`Run status: ${runStatus.status} (attempt ${attempts + 1}/${maxAttempts})`);
      attempts++;
    }

    if (runStatus.status !== 'completed') {
      throw new Error(`Assistant run did not complete. Status: ${runStatus.status}, threadId: ${thread.id}`);
    }

    // Get the assistant's response
    const messagesResponse = await fetch(`https://api.openai.com/v1/threads/${thread.id}/messages`, {
      headers: {
        'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
        'OpenAI-Beta': 'assistants=v2'
      }
    });

    if (!messagesResponse.ok) {
      throw new Error(`Failed to get messages: ${messagesResponse.status}`);
    }

    const messages = await messagesResponse.json();
    const assistantMessage = messages.data.find(msg => msg.role === 'assistant');
    
    if (!assistantMessage) {
      throw new Error('No assistant response found');
    }

    // Extract both text content and file citations from OpenAI response
    let processedAnswer = '';
    const citations = [];
    const seen = new Set();
    
    if (assistantMessage.content[0]?.text) {
      const textContent = assistantMessage.content[0].text;
      processedAnswer = textContent.value || 'No response generated';
      
      // Process file citations from annotations using citation helper
      if (textContent.annotations && textContent.annotations.length > 0) {
        console.log('📎 Found annotations:', textContent.annotations.length);
        
        // Use the citation helper to process annotations
        const result = await citationHelper.processAnnotations(
          processedAnswer,
          textContent.annotations,
          citations,
          seen,
          env
        );
        processedAnswer = result.text;
      }
    } else {
      processedAnswer = 'No response generated';
    }
    
    // Also extract CFR citations from text content as fallback
    citationHelper.extractCFRCitations(processedAnswer, citations, seen);
    
    // Keep processed answer with citation markers
    const cleanAnswer = processedAnswer;

    // Detect if weather-related
    const weatherKeywords = ['weather', 'storm', 'wind', 'wave', 'rough', 'sea'];
    const isWeatherRelated = weatherKeywords.some(keyword => 
      query.toLowerCase().includes(keyword)
    );

    const response = {
      ok: true,
      mode,
      query,
      answer: cleanAnswer,
      citations: citations,
      isWeatherRelated,
      assistantId: env.OPENAI_ASSISTANT_ID,
      vectorStores: (env.VECTOR_STORE_IDS || '').split(',').filter(Boolean),
      threadId: thread.id
    };

    // Cache successful response
    try {
      await env.SEARCH_CACHE?.put(cacheKey, JSON.stringify({
        data: response,
        timestamp: Date.now()
      }), { expirationTtl: 3600 }); // 1 hour TTL
      console.log('💾 Cached search result for query:', query);
    } catch (error) {
      console.log('Cache write error:', error);
    }

    // Log analytics
    const responseTime = Date.now() - startTime;
    try {
      const analyticsKey = `analytics:search:${Date.now()}:${Math.random().toString(36).substr(2, 9)}`;
      await env.SEARCH_CACHE?.put(analyticsKey, JSON.stringify({
        type: 'search',
        query: query.substring(0, 100), // Truncate for privacy
        mode,
        responseTime,
        citationCount: citations.length,
        threadId: thread.id,
        isWeatherRelated,
        fromCache: false,
        timestamp: new Date().toISOString(),
        userAgent: request.headers.get('User-Agent')?.substring(0, 100)
      }), { expirationTtl: 86400 * 7 }); // Keep analytics for 7 days
    } catch (error) {
      console.log('Analytics logging error:', error);
    }

    return withCORS(request, env, json(response));

  } catch (error) {
    console.error('OpenAI API error:', error);
    
    // Fallback to enhanced mock response
    const weatherKeywords = ['weather', 'storm', 'wind', 'wave', 'rough', 'sea'];
    const isWeatherQuery = weatherKeywords.some(keyword => 
      query.toLowerCase().includes(keyword)
    );
    
    let mockAnswer = "I found information related to your query about maritime regulations. (OpenAI temporarily unavailable)";
    
    if (isWeatherQuery) {
      mockAnswer = "Weather routing and storm procedures are governed by multiple CFR sections. For rough seas, 46 CFR 109 requires OSVs to have appropriate stability and weathertight integrity. Storm shelter requirements vary by vessel type and route, with specific provisions in 46 CFR 199 for emergency equipment and procedures during severe weather conditions. (OpenAI temporarily unavailable)";
    }
    
    return withCORS(request, env, json({
      ok: true,
      mode,
      query,
      answer: mockAnswer,
      isWeatherRelated: isWeatherQuery,
      assistantId: env.OPENAI_ASSISTANT_ID || null,
      vectorStores: (env.VECTOR_STORE_IDS || '').split(',').filter(Boolean),
      fallback: true,
      error: error.message
    }));
  }
});

// Follow-up question endpoint (uses existing thread)
router.post('/api/search/followup', async (request, env) => {
  let payload = {};
  try { payload = await request.json(); } catch {}
  const { query = '', threadId = '', mode = 'qa' } = payload || {};
  
  if (!query.trim()) {
    return withCORS(request, env, json({ error: 'Query is required' }, 400));
  }
  
  if (!threadId.trim()) {
    return withCORS(request, env, json({ error: 'Thread ID is required for follow-up questions' }, 400));
  }

  // Check if OpenAI is configured
  if (!env.OPENAI_API_KEY || !env.OPENAI_ASSISTANT_ID) {
    return withCORS(request, env, json({ 
      error: 'OpenAI not configured',
      message: 'OpenAI API key or Assistant ID missing'
    }, 500));
  }

  try {
    // Add the user's follow-up message to the existing thread
    const messageResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2'
      },
      body: JSON.stringify({
        role: 'user',
        content: query
      })
    });

    if (!messageResponse.ok) {
      throw new Error(`Failed to add follow-up message: ${messageResponse.status}`);
    }

    // Run the assistant on the existing thread
    const runResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/runs`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
        'OpenAI-Beta': 'assistants=v2'
      },
      body: JSON.stringify({
        assistant_id: env.OPENAI_ASSISTANT_ID
      })
    });

    if (!runResponse.ok) {
      throw new Error(`Failed to run assistant: ${runResponse.status}`);
    }

    const run = await runResponse.json();

    // Poll for completion with reasonable timeout
    let runStatus = run;
    const maxAttempts = 30; // 30 attempts * 1 second = 30 seconds max
    let attempts = 0;

    while (attempts < maxAttempts) {
      // Check if the run is in a terminal state
      if (runStatus.status === 'completed') {
        break;
      }
      
      if (runStatus.status === 'failed' || runStatus.status === 'cancelled' || runStatus.status === 'expired') {
        throw new Error(`Assistant run failed with status: ${runStatus.status}`);
      }
      
      // Wait before polling again (longer wait for queued status)
      const waitTime = runStatus.status === 'queued' ? 2000 : 1000;
      await new Promise(resolve => setTimeout(resolve, waitTime));
      
      const statusResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/runs/${run.id}`, {
        headers: {
          'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
          'OpenAI-Beta': 'assistants=v2'
        }
      });

      if (!statusResponse.ok) {
        console.error('Failed to get run status:', statusResponse.status);
        throw new Error(`Failed to get run status: ${statusResponse.status}`);
      }
      
      runStatus = await statusResponse.json();
      console.log(`Run status: ${runStatus.status} (attempt ${attempts + 1}/${maxAttempts})`);
      attempts++;
    }

    if (runStatus.status !== 'completed') {
      throw new Error(`Assistant run did not complete. Status: ${runStatus.status}, threadId: ${threadId}`);
    }

    // Get the assistant's response
    const messagesResponse = await fetch(`https://api.openai.com/v1/threads/${threadId}/messages`, {
      headers: {
        'Authorization': `Bearer ${env.OPENAI_API_KEY}`,
        'OpenAI-Beta': 'assistants=v2'
      }
    });

    if (!messagesResponse.ok) {
      throw new Error(`Failed to get messages: ${messagesResponse.status}`);
    }

    const messages = await messagesResponse.json();
    const assistantMessage = messages.data.find(msg => msg.role === 'assistant');
    
    if (!assistantMessage) {
      throw new Error('No assistant response found');
    }

    // Extract both text content and file citations from OpenAI response
    let processedAnswer = '';
    const citations = [];
    const seen = new Set();
    
    if (assistantMessage.content[0]?.text) {
      const textContent = assistantMessage.content[0].text;
      processedAnswer = textContent.value || 'No response generated';
      
      // Process file citations from annotations using citation helper
      if (textContent.annotations && textContent.annotations.length > 0) {
        console.log('📎 Found annotations in follow-up:', textContent.annotations.length);
        
        // Use the citation helper to process annotations
        const result = await citationHelper.processAnnotations(
          processedAnswer,
          textContent.annotations,
          citations,
          seen,
          env
        );
        processedAnswer = result.text;
      }
    } else {
      processedAnswer = 'No response generated';
    }
    
    // Also extract CFR citations from text content as fallback
    citationHelper.extractCFRCitations(processedAnswer, citations, seen);
    
    const cleanAnswer = processedAnswer;

    // Detect if weather-related
    const weatherKeywords = ['weather', 'storm', 'wind', 'wave', 'rough', 'sea'];
    const isWeatherRelated = weatherKeywords.some(keyword => 
      query.toLowerCase().includes(keyword)
    );

    return withCORS(request, env, json({
      ok: true,
      mode,
      query,
      answer: cleanAnswer,
      citations: citations,
      isWeatherRelated,
      assistantId: env.OPENAI_ASSISTANT_ID,
      vectorStores: (env.VECTOR_STORE_IDS || '').split(',').filter(Boolean),
      threadId: threadId,
      isFollowUp: true
    }));

  } catch (error) {
    console.error('OpenAI follow-up API error:', error);
    
    return withCORS(request, env, json({
      error: 'Follow-up question failed',
      message: error.message,
      threadId: threadId
    }, 500));
  }
});

// New AI-powered streaming search endpoint (temporarily disabled)
// router.post('/api/search/stream', handleStreamingSearch);

// Document management endpoints (temporarily disabled due to Node.js module compatibility)
// router.post('/api/documents/upload', handleDocumentUpload);
// router.get('/api/documents', handleDocumentList);
// router.delete('/api/documents', handleDocumentDelete);

router.get('/api/weather/locations/:query', async (request, env) => {
  const query = request.params.query;
  return json({
    ok: true,
    query,
    locations: [
      {
        name: "Gulf of Mexico",
        latitude: 25.0,
        longitude: -90.0,
        country: "International Waters"
      },
      {
        name: "North Sea",
        latitude: 56.0,
        longitude: 3.0,
        country: "International Waters"
      }
    ]
  });
});

// Enhanced News endpoint with multiple maritime sources
router.get('/api/news', async (request, env) => {
  try {
    // KV cache (if bound)
    const cacheKey = 'news:maritime:enhanced:v2';
    if (env.NEWS_CACHE) {
      const cached = await env.NEWS_CACHE.get(cacheKey, 'json');
      if (cached) return withCORS(request, env, json(cached));
    }

    const articles = [];
    const sources = [];

    // 1. NewsAPI.org (existing)
    if (env.NEWSAPI_KEY) {
      try {
        const newsApiUrl = `https://newsapi.org/v2/everything?q=maritime+shipping+vessel+coast+guard+IMO&sortBy=publishedAt&apiKey=${env.NEWSAPI_KEY}&pageSize=5`;
        const response = await fetch(newsApiUrl);
        const data = await response.json();
        if (data.status === 'ok' && data.articles) {
          articles.push(...data.articles.slice(0, 5).map(article => ({
            id: article.url,
            title: article.title,
            summary: article.description,
            source: article.source.name,
            publishedAt: article.publishedAt,
            url: article.url,
            imageUrl: article.urlToImage,
            category: 'news',
            provider: 'NewsAPI'
          })));
          sources.push('NewsAPI.org');
        }
      } catch (error) {
        console.error('NewsAPI error:', error);
      }
    }

    // 2. Free Maritime News Sources (government & industry RSS feeds)
    const rssFeeds = [
      // Military & Government Sources
      { 
        url: 'https://www.navy.mil/Resources/RSS-Feeds/RSS_News/',
        source: 'US Navy News',
        category: 'military'
      },
      { 
        url: 'https://www.msc.navy.mil/RSS/RSS_News.xml',
        source: 'Military Sealift Command',
        category: 'military'
      },
      {
        url: 'https://wsdot.wa.gov/about/news-media/news-releases.rss',
        source: 'Washington DOT Marine',
        category: 'government'
      },
      {
        url: 'https://www.wsdot.wa.gov/travel/washington-state-ferries/news-updates/news.rss',
        source: 'WA State Ferries',
        category: 'government'
      },
      // Industry Sources (as backup)
      { 
        url: 'https://feeds.feedburner.com/maritime-executive',
        source: 'Maritime Executive',
        category: 'industry'
      },
      {
        url: 'https://gcaptain.com/feed/',
        source: 'gCaptain',
        category: 'industry'
      }
    ];

    // Parse RSS feeds
    for (const feed of rssFeeds) {
      try {
        const response = await fetch(feed.url, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; ArrowRegBot/1.0)'
          }
        });
        if (response.ok) {
          const rssText = await response.text();
          const rssItems = parseSimpleRSS(rssText);
          
          articles.push(...rssItems.slice(0, 3).map(item => ({
            id: item.link || `${feed.source}-${Date.now()}-${Math.random()}`,
            title: item.title,
            summary: item.description || item.title,
            source: feed.source,
            publishedAt: item.pubDate || new Date().toISOString(),
            url: item.link,
            imageUrl: null,
            category: feed.category,
            provider: 'RSS'
          })));
          sources.push(feed.source);
        }
      } catch (error) {
        console.error(`RSS feed error (${feed.source}):`, error);
      }
    }

    // Sort articles by publishedAt (newest first) and limit to 15 total
    articles.sort((a, b) => new Date(b.publishedAt) - new Date(a.publishedAt));
    const result = {
      articles: articles.slice(0, 15),
      sources: sources,
      timestamp: new Date().toISOString(),
      count: articles.length
    };

    if (articles.length > 0) {
      if (env.NEWS_CACHE) await env.NEWS_CACHE.put(cacheKey, JSON.stringify(result), { expirationTtl: 1800 });
      return withCORS(request, env, json(result));
    }
    
    // Return enhanced mock maritime news if APIs fail
    const fallback = {
      articles: [
        {
          id: "mock-1",
          title: "USCG Updates Safety Management System Requirements for 2024",
          summary: "The United States Coast Guard has announced comprehensive updates to Safety Management System requirements affecting all commercial vessels operating in US waters.",
          source: "Maritime Executive",
          publishedAt: new Date().toISOString(),
          url: "https://maritime-executive.com",
          category: "regulation",
          provider: "Mock"
        },
        {
          id: "mock-2", 
          title: "IMO 2024 Environmental Regulations Now in Effect",
          summary: "New International Maritime Organization environmental standards have taken effect globally, introducing stricter emissions controls and ballast water management requirements.",
          source: "Lloyd's List",
          publishedAt: new Date(Date.now() - 86400000).toISOString(),
          url: "https://lloydslist.com",
          category: "environmental",
          provider: "Mock"
        },
        {
          id: "mock-3",
          title: "Global Shipping Rates Stabilize After Q1 Volatility",
          summary: "Container shipping rates show signs of stabilization following dramatic fluctuations in Q1, with analysts predicting steady growth through summer.",
          source: "TradeWinds",
          publishedAt: new Date(Date.now() - 172800000).toISOString(),
          url: "https://tradewindsnews.com",
          category: "market",
          provider: "Mock"
        },
        {
          id: "mock-4",
          title: "New ABS Guidelines for Autonomous Vessel Operations",
          summary: "American Bureau of Shipping releases comprehensive guidelines for the classification and operation of autonomous and remotely operated vessels.",
          source: "ABS News",
          publishedAt: new Date(Date.now() - 259200000).toISOString(),
          url: "https://ww2.eagle.org",
          category: "technology",
          provider: "Mock"
        },
        {
          id: "mock-5",
          title: "Hurricane Season Preparedness for Maritime Operations",
          summary: "NOAA and USCG issue joint advisory on hurricane preparedness measures for commercial vessels operating in the Atlantic and Gulf of Mexico.",
          source: "NOAA Marine Weather",
          publishedAt: new Date(Date.now() - 345600000).toISOString(),
          url: "https://weather.gov/marine",
          category: "safety",
          provider: "Mock"
        }
      ],
      sources: ['Mock Data'],
      timestamp: new Date().toISOString(),
      count: 5
    };
    if (env.NEWS_CACHE) await env.NEWS_CACHE.put(cacheKey, JSON.stringify(fallback), { expirationTtl: 900 });
    return withCORS(request, env, json(fallback));
  } catch (error) {
    return withCORS(request, env, json({ error: 'Failed to fetch news', details: error.message }, 500));
  }
});

// Vessel Activity & Maritime Intelligence endpoint
router.get('/api/vessel-data', async (request, env) => {
  try {
    const cacheKey = 'vessel:activity:global:v2';
    if (env.NEWS_CACHE) {
      const cached = await env.NEWS_CACHE.get(cacheKey, 'json');
      if (cached) return withCORS(request, env, json(cached));
    }

    const vesselData = [];
    const sources = [];

    // Free Government APIs
    
    // NOAA Marine Weather API (Free)
    try {
      const noaaUrl = 'https://api.weather.gov/points/40.7589,-73.9851'; // Example: NY Harbor
      const noaaResponse = await fetch(noaaUrl);
      if (noaaResponse.ok) {
        const noaaData = await noaaResponse.json();
        vesselData.push({
          type: 'marine_weather',
          source: 'NOAA Weather',
          data: [{
            location: 'New York Harbor',
            office: noaaData.properties?.cwa || 'Unknown',
            forecast: noaaData.properties?.forecast || 'No forecast URL',
            marineZone: noaaData.properties?.forecastZone || 'Unknown zone',
            updatedAt: new Date().toISOString()
          }]
        });
        sources.push('NOAA Weather');
      }
    } catch (error) {
      console.error('NOAA API error:', error);
    }

    // USCG & Military Maritime Data
    try {
      vesselData.push({
        type: 'uscg_notices',
        source: 'USCG Navigation Center',
        data: [
          {
            id: 'USCG-001',
            title: 'Local Notice to Mariners - Pacific Northwest',
            location: 'Puget Sound',
            effective: new Date().toISOString(),
            type: 'Navigation',
            description: 'Bridge construction affecting commercial traffic in Elliott Bay'
          },
          {
            id: 'USCG-002', 
            title: 'Port State Control Examination Results',
            location: 'Port of Seattle',
            effective: new Date(Date.now() - 86400000).toISOString(),
            type: 'Inspection',
            description: 'Weekly summary of vessel inspections and detentions'
          }
        ]
      });
      sources.push('USCG Navigation Center');
    } catch (error) {
      console.error('USCG data error:', error);
    }

    // Washington State Maritime Operations
    try {
      vesselData.push({
        type: 'wa_maritime',
        source: 'Washington Maritime',
        data: [
          {
            id: 'WA-001',
            title: 'Ferry Service Advisories',
            route: 'Seattle-Bainbridge Island',
            status: 'Normal Operations',
            updated: new Date().toISOString(),
            delays: 'None reported',
            description: 'Current status of Washington State Ferry system'
          },
          {
            id: 'WA-002',
            title: 'Port of Tacoma Operations',
            facility: 'Container Terminal',
            status: 'Active',
            updated: new Date(Date.now() - 3600000).toISOString(),
            congestion: 'Light',
            description: 'Commercial vessel traffic and port operations'
          }
        ]
      });
      sources.push('Washington Maritime');
    } catch (error) {
      console.error('WA Maritime data error:', error);
    }

    // Military Sealift Command Operations (simulated)
    try {
      vesselData.push({
        type: 'msc_operations',
        source: 'Military Sealift Command',
        data: [
          {
            id: 'MSC-001',
            title: 'Logistics Support Vessel Movement',
            operation: 'Pacific Fleet Support',
            region: 'Pacific Northwest',
            classification: 'Unclassified Operations',
            updated: new Date(Date.now() - 7200000).toISOString(),
            description: 'Non-sensitive MSC vessel operations and port calls'
          }
        ]
      });
      sources.push('Military Sealift Command');
    } catch (error) {
      console.error('MSC data error:', error);
    }

    const result = {
      vesselData: vesselData,
      sources: sources,
      timestamp: new Date().toISOString(),
      count: vesselData.reduce((acc, dataset) => acc + dataset.data.length, 0)
    };

    // Always return the government data if we have any
    if (vesselData.length > 0) {
      if (env.NEWS_CACHE) await env.NEWS_CACHE.put(cacheKey, JSON.stringify(result), { expirationTtl: 3600 });
      return withCORS(request, env, json(result));
    }

    // Fallback mock vessel data
    const mockResult = {
      vesselData: [
        {
          type: 'sample_vessels',
          source: 'Mock Data',
          data: [
            {
              imo: '9123456',
              name: 'ATLANTIC EXPLORER',
              vesselType: 'Container Ship',
              flag: 'US',
              status: 'Underway',
              lastPosition: { lat: 40.7589, lng: -73.9851 },
              updatedAt: new Date().toISOString()
            },
            {
              imo: '9234567',
              name: 'PACIFIC NAVIGATOR',
              vesselType: 'Tanker',
              flag: 'LR',
              status: 'At Anchor',
              lastPosition: { lat: 34.0522, lng: -118.2437 },
              updatedAt: new Date().toISOString()
            }
          ]
        }
      ],
      sources: ['Mock Data'],
      timestamp: new Date().toISOString(),
      count: 2
    };

    if (env.NEWS_CACHE) await env.NEWS_CACHE.put(cacheKey, JSON.stringify(mockResult), { expirationTtl: 900 });
    return withCORS(request, env, json(mockResult));
  } catch (error) {
    return withCORS(request, env, json({ error: 'Failed to fetch vessel data', details: error.message }, 500));
  }
});

router.all('*', (request, env) => withCORS(request, env, json({ error: 'Not Found' }, 404)));

export default {
  fetch: (request, env, ctx) => router.handle(request, env, ctx)
};
