import LocalSearchService from '../services/local-search.js';
import { startStream, sendEvent, closeStream } from '../utils/sse.js';

const localSearchService = new LocalSearchService();

export async function handleLocalSearch(request) {
    try {
        const { query, mode = 'qa', filters = {}, maxResults = 10 } = request;

        if (!query || query.trim().length < 2) {
            throw new Error('Query must be at least 2 characters long');
        }

        // Map regulation sources to document IDs
        const sourceMapping = {
            'cfr33': 'cfr33',
            'cfr46': 'cfr46', 
            'abs': 'abs_part7'
        };

        const sources = [];
        if (filters.sources && Array.isArray(filters.sources)) {
            for (const source of filters.sources) {
                if (sourceMapping[source.toLowerCase()]) {
                    sources.push(sourceMapping[source.toLowerCase()]);
                }
            }
        }

        // Perform local search
        const searchOptions = {
            maxResults: maxResults * 2, // Get more results to filter and rank
            minRelevanceScore: 0.15,
            sources: sources
        };

        const localResults = await localSearchService.search(query, searchOptions);

        if (mode === 'qa') {
            return formatAsQAResponse(query, localResults, maxResults);
        } else {
            return formatAsSearchResults(localResults, maxResults);
        }

    } catch (error) {
        console.error('Local search error:', error);
        throw error;
    }
}

function formatAsQAResponse(query, searchResults, maxResults) {
    if (searchResults.length === 0) {
        return {
            id: generateId(),
            answer: `I couldn't find specific information about "${query}" in the local regulation documents. This search was performed offline using CFR 33, CFR 46, and ABS Part 7 regulations.`,
            citations: [],
            confidence: 0,
            isComplete: true,
            isOffline: true,
            timestamp: new Date().toISOString()
        };
    }

    // Generate comprehensive answer from top results
    const topResults = searchResults.slice(0, Math.min(5, maxResults));
    const answer = generateAnswer(query, topResults);
    const citations = formatCitations(topResults);

    // Calculate overall confidence
    const avgConfidence = topResults.reduce((sum, result) => sum + result.confidence, 0) / topResults.length;

    return {
        id: generateId(),
        answer: answer,
        citations: citations,
        confidence: Math.round(avgConfidence),
        isComplete: true,
        isOffline: true,
        timestamp: new Date().toISOString(),
        sourceInfo: {
            searchedDocuments: ['33 CFR', '46 CFR', 'ABS Part 7'],
            totalMatches: searchResults.length
        }
    };
}

function generateAnswer(query, results) {
    if (results.length === 0) return '';

    // Create a comprehensive answer by combining relevant content
    let answer = `Based on the maritime regulations, here's what I found regarding "${query}":\n\n`;

    // Group results by document for better organization
    const resultsByDoc = {};
    for (const result of results.slice(0, 3)) { // Use top 3 results
        const docName = result.source.displayName;
        if (!resultsByDoc[docName]) {
            resultsByDoc[docName] = [];
        }
        resultsByDoc[docName].push(result);
    }

    // Generate answer sections
    for (const [docName, docResults] of Object.entries(resultsByDoc)) {
        answer += `**${docName}:**\n`;
        
        for (const result of docResults) {
            // Extract the most relevant part of the content
            const relevantContent = extractRelevantContent(result.content, query);
            const sectionRef = result.sectionNumber ? ` (${result.sectionNumber})` : '';
            
            answer += `- ${result.title}${sectionRef}: ${relevantContent}\n`;
        }
        answer += '\n';
    }

    answer += `\nThis search was performed using offline regulation documents. For the most current information, consider checking the latest versions of these regulations online.`;

    return answer.trim();
}

function extractRelevantContent(content, query, maxLength = 200) {
    if (!content) return '';

    const queryWords = query.toLowerCase().split(/\s+/).filter(w => w.length > 2);
    const sentences = content.split(/[.!?]+/).filter(s => s.trim().length > 10);

    // Find sentences containing query words
    const relevantSentences = sentences
        .map(sentence => ({
            text: sentence.trim(),
            score: queryWords.reduce((score, word) => 
                score + (sentence.toLowerCase().includes(word) ? 1 : 0), 0)
        }))
        .filter(s => s.score > 0)
        .sort((a, b) => b.score - a.score);

    if (relevantSentences.length === 0) {
        // Fallback to first meaningful sentence
        return sentences[0] ? sentences[0].trim().substring(0, maxLength) + '...' : content.substring(0, maxLength) + '...';
    }

    let result = relevantSentences[0].text;
    if (result.length > maxLength) {
        result = result.substring(0, maxLength) + '...';
    }

    return result;
}

function formatCitations(results) {
    return results.slice(0, 8).map(result => ({
        id: result.sectionId,
        title: result.title,
        section: result.sectionNumber || result.title,
        source: {
            name: result.source.name,
            displayName: result.source.displayName,
            type: result.source.type
        },
        url: null, // Local documents don't have URLs
        relevanceScore: result.confidence / 100,
        isOffline: true
    }));
}

function formatAsSearchResults(results, maxResults) {
    return {
        results: results.slice(0, maxResults).map(result => ({
            id: result.sectionId,
            title: result.title,
            content: result.content,
            source: result.source,
            confidence: result.confidence,
            sectionNumber: result.sectionNumber,
            matchingWords: result.matchingWords,
            isOffline: true
        })),
        totalFound: results.length,
        isOffline: true,
        timestamp: new Date().toISOString()
    };
}

function generateId() {
    return 'local_' + Math.random().toString(36).substr(2, 9) + Date.now().toString(36);
}

export function handleLocalStreamSearch(request) {
    return startStream(async (controller, encoder) => {
        sendEvent(controller, encoder, 'content', 'Searching local regulations...\n\n');

        // Small delay to show searching state
        await new Promise(resolve => setTimeout(resolve, 500));

        const result = await handleLocalSearch(request);

        // Stream the answer word by word for consistency with OpenAI
        const words = result.answer.split(' ');
        const chunkSize = 8;

        for (let i = 0; i < words.length; i += chunkSize) {
            const chunk = words.slice(i, i + chunkSize).join(' ') + ' ';
            sendEvent(controller, encoder, 'content', chunk);
            await new Promise(resolve => setTimeout(resolve, 50));
        }

        // Send citations
        for (const citation of result.citations) {
            sendEvent(controller, encoder, 'citation', citation);
        }

        sendEvent(controller, encoder, 'confidence', result.confidence);
        sendEvent(controller, encoder, 'done', null);
        closeStream(controller);
    });
}
