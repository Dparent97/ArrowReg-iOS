import OpenAI from 'openai';
import { handleLocalSearch, handleLocalStreamSearch } from './local-search.js';

/**
 * OpenAI-powered maritime compliance search handler
 * Provides intelligent responses with CFR citations using vector stores
 */

export class OpenAISearchHandler {
  constructor(env) {
    this.env = env;
    this.openai = new OpenAI({
      apiKey: env.OPENAI_API_KEY
    });
    this.assistantId = env.OPENAI_ASSISTANT_ID;
  }

  /**
   * Perform streaming search using OpenAI assistant
   */
  async performSearch(query, mode = 'qa', additionalContext = '') {
    // Check if OpenAI is available
    if (!this.env.OPENAI_API_KEY || !this.assistantId) {
      console.log('OpenAI not available, using local search fallback');
      return await handleLocalSearch({
        query,
        mode,
        filters: {},
        maxResults: 10
      });
    }

    try {
      // Create a thread for this conversation
      const thread = await this.openai.beta.threads.create();

      // Prepare the message with context
      let messageContent = query;
      
      if (additionalContext) {
        messageContent = `${messageContent}\n\nAdditional Context: ${additionalContext}`;
      }

      // Add mode-specific instructions
      const modeInstructions = this.getModeInstructions(mode);
      if (modeInstructions) {
        messageContent = `${modeInstructions}\n\n${messageContent}`;
      }

      // Add the user message
      await this.openai.beta.threads.messages.create(
        thread.id,
        {
          role: 'user',
          content: messageContent
        }
      );

      // Start the run
      const run = await this.openai.beta.threads.runs.create(
        thread.id,
        {
          assistant_id: this.assistantId,
          temperature: 0.1,
          max_prompt_tokens: 4000,
          max_completion_tokens: 2000
        }
      );

      return await this.waitForCompletion(run, thread.id);

    } catch (error) {
      console.error('OpenAI search error:', error);
      throw new Error(`Search failed: ${error.message}`);
    }
  }

  /**
   * Wait for completion and return structured response
   */
  async waitForCompletion(run, threadId, timeoutMs = 30000) {
    let currentMessage = '';
    let citations = [];
    let functionCalls = [];

    const startTime = Date.now();
    let delayMs = 500;
    let attempts = 0;

    try {
      // Poll for completion
      while (Date.now() - startTime < timeoutMs) {
        attempts++;
        console.log(`Polling attempt ${attempts}`);

        const currentRun = await this.openai.beta.threads.runs.retrieve(
          threadId,
          run.id
        );

        if (currentRun.status === 'requires_action') {
          // Handle function calls
          if (currentRun.required_action?.type === 'submit_tool_outputs') {
            const toolCalls = currentRun.required_action.submit_tool_outputs.tool_calls;
            const toolOutputs = await this.handleToolCalls(toolCalls);
            
            await this.openai.beta.threads.runs.submitToolOutputs(
              threadId,
              run.id,
              {
                tool_outputs: toolOutputs
              }
            );
          }
          
        } else if (currentRun.status === 'completed') {
          // Get the assistant's response
          const messages = await this.openai.beta.threads.messages.list(
            threadId,
            { order: 'desc', limit: 1 }
          );

          if (messages.data.length > 0) {
            const message = messages.data[0];
            for (const content of message.content) {
              if (content.type === 'text') {
                currentMessage = content.text.value;
                citations = this.extractCitations(currentMessage);
              }
            }
          }

          // Return structured response
          const uniqueCitations = this.deduplicateCitations(citations);
          const confidence = this.calculateConfidence(currentMessage, uniqueCitations);
          
          return {
            message: currentMessage,
            citations: uniqueCitations,
            confidence: confidence,
            success: true
          };

        } else if (currentRun.status === 'failed') {
          throw new Error(`OpenAI run failed: ${currentRun.last_error?.message || 'Unknown error'}`);
        }

        // Wait before next poll with exponential backoff
        await this.delay(delayMs);
        delayMs = Math.min(delayMs * 2, 5000);
      }

      throw new Error('OpenAI request timed out');

    } catch (error) {
      console.error('Polling error:', error);
      throw error;
    }
  }

  /**
   * Simple delay helper
   */
  delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Get mode-specific instructions
   */
  getModeInstructions(mode) {
    const instructions = {
      'qa': 'Provide a direct, comprehensive answer with specific CFR citations. Focus on practical compliance requirements.',
      'section': 'Find and explain the specific regulation sections that address this query. Include exact section numbers and titles.',
      'compare': 'Compare and contrast the different regulatory approaches. Highlight similarities, differences, and when each applies.'
    };

    return instructions[mode] || instructions['qa'];
  }

  /**
   * Extract regulation citations from text
   */
  extractCitations(text) {
    const citations = [];
    
    // Regex patterns for different citation formats
    const patterns = [
      /\b(\d+)\s+CFR\s+(\d+(?:\.\d+)*)\b/gi,          // 46 CFR 109.213
      /\bTitle\s+(\d+),?\s+CFR\s+(\d+(?:\.\d+)*)\b/gi, // Title 46 CFR 109.213
      /\b(ABS)\s+([A-Z0-9-]+(?:\.[A-Z0-9-]+)*)\b/gi,   // ABS rules
      /\b(NVIC)\s+(\d+-\d+)\b/gi,                       // NVIC 01-14
      /\b(MSM)\s+Volume\s+(\d+)\b/gi                    // MSM Volume references
    ];

    for (const pattern of patterns) {
      let match;
      while ((match = pattern.exec(text)) !== null) {
        const [fullMatch, part1, part2] = match;
        
        let source, section, title;
        
        if (part1 === 'ABS') {
          source = 'ABS Rules';
          section = part2;
          title = 'ABS Classification Rule';
        } else if (part1 === 'NVIC') {
          source = 'NVIC';
          section = part2;
          title = 'Navigation and Vessel Inspection Circular';
        } else if (part1 === 'MSM') {
          source = 'Marine Safety Manual';
          section = `Volume ${part2}`;
          title = 'Marine Safety Manual';
        } else {
          // CFR citation
          source = part1 === '33' ? 'CFR Title 33' : part1 === '46' ? 'CFR Title 46' : `CFR Title ${part1}`;
          section = `${part1} CFR ${part2}`;
          title = this.getCFRSectionTitle(part1, part2);
        }

        citations.push({
          id: `${source}-${section}`.replace(/\s+/g, '-'),
          source,
          section,
          title,
          relevanceScore: 0.9 // High relevance since it came from AI response
        });
      }
    }

    return citations;
  }

  /**
   * Get approximate CFR section titles
   */
  getCFRSectionTitle(title, section) {
    // Common CFR section mappings
    const sectionTitles = {
      '33': {
        '151': 'Vessels carrying oil, noxious liquid substances, garbage, municipal or commercial waste, and ballast water',
        '160': 'Ports and Waterways Safety'
      },
      '46': {
        '109': 'Offshore Supply Vessels',
        '199': 'Lifesaving Systems and Arrangements',
        '185': 'Oceanographic Research Vessels'
      }
    };

    const majorSection = section.split('.')[0];
    return sectionTitles[title]?.[majorSection] || 'Maritime Regulation';
  }

  /**
   * Handle tool calls (e.g., weather function)
   */
  async handleToolCalls(toolCalls) {
    const toolOutputs = [];

    for (const toolCall of toolCalls) {
      if (toolCall.function?.name === 'get_weather_conditions') {
        try {
          const args = JSON.parse(toolCall.function.arguments);
          const weatherData = await this.getWeatherConditions(args);
          
          toolOutputs.push({
            tool_call_id: toolCall.id,
            output: JSON.stringify(weatherData)
          });
        } catch (error) {
          toolOutputs.push({
            tool_call_id: toolCall.id,
            output: JSON.stringify({ error: 'Weather data unavailable' })
          });
        }
      }
    }

    return toolOutputs;
  }

  /**
   * Get weather conditions for regulatory context
   */
  async getWeatherConditions({ latitude, longitude, vessel_type }) {
    // This would integrate with the weather service
    // For now, return mock data
    return {
      location: { latitude, longitude },
      conditions: {
        wave_height: 1.5,
        wind_speed: 15,
        visibility: 10,
        sea_state: 'moderate'
      },
      vessel_suitability: vessel_type === 'OSV' ? 'suitable' : 'check_conditions',
      regulatory_notes: [
        'Current conditions within normal operational limits',
        'Monitor weather updates for changes'
      ]
    };
  }

  /**
   * Remove duplicate citations
   */
  deduplicateCitations(citations) {
    const seen = new Set();
    return citations.filter(citation => {
      const key = `${citation.source}-${citation.section}`;
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
  }

  /**
   * Calculate response confidence based on various factors
   */
  calculateConfidence(message, citations) {
    let confidence = 70; // Base confidence

    // Increase confidence based on citations
    confidence += Math.min(citations.length * 5, 20);

    // Increase confidence for longer, detailed responses
    if (message.length > 200) confidence += 5;
    if (message.length > 500) confidence += 5;

    // Decrease confidence for very short responses
    if (message.length < 50) confidence -= 10;

    // Cap confidence
    return Math.min(Math.max(confidence, 50), 95);
  }
}

/**
 * Handle search requests with streaming response
 */
export async function handleStreamingSearch(request, env) {
  try {
    const { query, mode = 'qa', context, filters } = await request.json();
    
    if (!query?.trim()) {
      return new Response('Query is required', { status: 400 });
    }

    // Check if OpenAI is available, otherwise use local search
    if (!env.OPENAI_API_KEY || !env.OPENAI_ASSISTANT_ID) {
      console.log('OpenAI not available, streaming local search results');
      return await streamLocalSearchResponse({
        query: query.trim(),
        mode,
        filters: filters || {},
        maxResults: 10
      });
    }

    const searchHandler = new OpenAISearchHandler(env);

    // Create Server-Sent Events stream
    const encoder = new TextEncoder();
    const readable = new ReadableStream({
      async start(controller) {
        try {
          // Get the complete response from OpenAI
          const result = await searchHandler.performSearch(query.trim(), mode, context);
          
          if (result.success) {
            // Simulate streaming by breaking up the response
            const words = result.message.split(' ');
            const chunkSize = 3;
            
            for (let i = 0; i < words.length; i += chunkSize) {
              const chunk = words.slice(i, i + chunkSize).join(' ');
              const data = `data: ${JSON.stringify({
                type: 'content',
                data: chunk + (i + chunkSize < words.length ? ' ' : '')
              })}\n\n`;
              
              controller.enqueue(encoder.encode(data));
              
              // Small delay to simulate streaming
              await new Promise(resolve => setTimeout(resolve, 100));
            }
            
            // Send citations
            for (const citation of result.citations) {
              const data = `data: ${JSON.stringify({
                type: 'citation',
                data: citation
              })}\n\n`;
              controller.enqueue(encoder.encode(data));
            }
            
            // Send confidence
            const confidenceData = `data: ${JSON.stringify({
              type: 'confidence',
              data: result.confidence
            })}\n\n`;
            controller.enqueue(encoder.encode(confidenceData));
            
            // Send completion
            const doneData = `data: ${JSON.stringify({
              type: 'done',
              data: result
            })}\n\n`;
            controller.enqueue(encoder.encode(doneData));
            
          } else {
            throw new Error('Search failed');
          }
          
          // Send final done event
          controller.enqueue(encoder.encode('data: {"type":"stream_end"}\n\n'));
          controller.close();
          
        } catch (error) {
          console.error('Stream processing error:', error);
          const errorData = `data: ${JSON.stringify({
            type: 'error',
            data: error.message
          })}\n\n`;
          controller.enqueue(encoder.encode(errorData));
          controller.close();
        }
      }
    });

    return new Response(readable, {
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Allow-Methods': 'POST, OPTIONS'
      }
    });

  } catch (error) {
    console.error('Streaming search error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        status: 500,
        headers: { 
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      }
    );
  }
}

/**
 * Stream local search results as Server-Sent Events
 */
async function streamLocalSearchResponse(searchRequest) {
  try {
    const encoder = new TextEncoder();
    const readable = new ReadableStream({
      async start(controller) {
        try {
          // Perform local search
          const result = await handleLocalSearch(searchRequest);
          
          // Stream initial searching message
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({
            type: 'content',
            data: 'Searching offline regulation documents...\n\n'
          })}\n\n`));
          
          // Small delay
          await new Promise(resolve => setTimeout(resolve, 300));
          
          // Stream the answer word by word
          if (result.answer) {
            const words = result.answer.split(' ');
            const chunkSize = 5;
            
            for (let i = 0; i < words.length; i += chunkSize) {
              const chunk = words.slice(i, i + chunkSize).join(' ') + ' ';
              controller.enqueue(encoder.encode(`data: ${JSON.stringify({
                type: 'content',
                data: chunk
              })}\n\n`));
              
              // Small delay for realistic streaming
              await new Promise(resolve => setTimeout(resolve, 50));
            }
          }
          
          // Stream citations
          for (const citation of result.citations || []) {
            controller.enqueue(encoder.encode(`data: ${JSON.stringify({
              type: 'citation',
              data: citation
            })}\n\n`));
          }
          
          // Stream confidence
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({
            type: 'confidence',
            data: result.confidence
          })}\n\n`));
          
          // Signal completion
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({
            type: 'done',
            data: null
          })}\n\n`));
          
          controller.close();
          
        } catch (error) {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({
            type: 'error',
            data: `Local search error: ${error.message}`
          })}\n\n`));
          controller.close();
        }
      }
    });

    return new Response(readable, {
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Allow-Methods': 'POST, OPTIONS'
      }
    });
    
  } catch (error) {
    console.error('Local streaming error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        status: 500,
        headers: { 
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      }
    );
  }
}