import { marked } from 'marked';
import fs from 'node:fs';
import path from 'node:path';

class LocalSearchService {
    constructor() {
        this.searchIndex = new Map();
        this.documents = new Map();
        this.initialized = false;
    }

    async initialize() {
        if (this.initialized) return;

        const documentsPath = path.join(process.cwd(), '..', 'data-local');
        
        try {
            await this.loadDocument(path.join(documentsPath, 'ABS-Part-7-Structured.md'), 'abs_part7');
            await this.loadDocument(path.join(documentsPath, 'ECFR-title33.md'), 'cfr33');
            await this.loadDocument(path.join(documentsPath, 'ECFR-title46.md'), 'cfr46');
            
            console.log(`Loaded ${this.documents.size} documents for local search`);
            this.initialized = true;
        } catch (error) {
            console.error('Failed to initialize local search:', error);
            throw error;
        }
    }

    async loadDocument(filePath, documentId) {
        try {
            const content = await fs.promises.readFile(filePath, 'utf8');
            const sections = this.parseMarkdownSections(content, documentId);
            
            this.documents.set(documentId, {
                id: documentId,
                title: this.getDocumentTitle(documentId),
                sections: sections,
                fullContent: content
            });

            // Build search index for this document
            this.indexDocument(documentId, sections);
            
        } catch (error) {
            console.error(`Failed to load document ${documentId}:`, error);
            throw error;
        }
    }

    parseMarkdownSections(content, documentId) {
        const lines = content.split('\n');
        const sections = [];
        let currentSection = null;
        let currentContent = '';

        for (const line of lines) {
            // Detect section headers (# ## ### #### etc.)
            const headerMatch = line.match(/^(#{1,6})\s+(.+)$/);
            
            if (headerMatch) {
                // Save previous section if it exists
                if (currentSection) {
                    sections.push({
                        ...currentSection,
                        content: currentContent.trim(),
                        wordCount: currentContent.trim().split(/\s+/).length
                    });
                }

                // Start new section
                const level = headerMatch[1].length;
                const title = headerMatch[2].trim();
                
                currentSection = {
                    id: `${documentId}_${sections.length}`,
                    title: title,
                    level: level,
                    documentId: documentId,
                    sectionNumber: this.extractSectionNumber(title)
                };
                currentContent = '';
            } else if (currentSection && line.trim()) {
                currentContent += line + '\n';
            }
        }

        // Don't forget the last section
        if (currentSection) {
            sections.push({
                ...currentSection,
                content: currentContent.trim(),
                wordCount: currentContent.trim().split(/\s+/).length
            });
        }

        return sections;
    }

    extractSectionNumber(title) {
        // Extract section numbers like "§ 1.01-1", "Chapter 1", "Part 7", etc.
        const patterns = [
            /§\s*(\d+(?:\.\d+)*(?:-\d+)*)/,  // CFR sections like § 1.01-1
            /Chapter\s+(\d+)/i,              // Chapters
            /Part\s+(\d+)/i,                 // Parts
            /Section\s+(\d+)/i               // Sections
        ];

        for (const pattern of patterns) {
            const match = title.match(pattern);
            if (match) {
                return match[1];
            }
        }

        return null;
    }

    getDocumentTitle(documentId) {
        const titles = {
            'abs_part7': 'ABS Part 7: Survey After Construction',
            'cfr33': '33 CFR: Navigation and Navigable Waters',
            'cfr46': '46 CFR: Shipping'
        };
        return titles[documentId] || documentId;
    }

    indexDocument(documentId, sections) {
        for (const section of sections) {
            const words = this.extractKeywords(section.title + ' ' + section.content);
            
            for (const word of words) {
                if (!this.searchIndex.has(word)) {
                    this.searchIndex.set(word, []);
                }
                
                this.searchIndex.get(word).push({
                    documentId: documentId,
                    sectionId: section.id,
                    title: section.title,
                    relevanceScore: this.calculateRelevanceScore(word, section),
                    sectionNumber: section.sectionNumber
                });
            }
        }
    }

    extractKeywords(text) {
        // Convert to lowercase and extract meaningful words
        const words = text.toLowerCase()
            .replace(/[^\w\s]/g, ' ')
            .split(/\s+/)
            .filter(word => 
                word.length > 2 && 
                !this.isStopWord(word) &&
                !word.match(/^\d+$/) // Filter pure numbers
            );

        // Add important maritime terms and phrases
        const maritimeTerms = this.extractMaritimeTerms(text);
        
        return [...new Set([...words, ...maritimeTerms])];
    }

    extractMaritimeTerms(text) {
        const maritimePatterns = [
            /\b(fire\s+detection|life\s+saving|oil\s+discharge|manning\s+requirements)\b/gi,
            /\b(osv|offshore\s+supply\s+vessel|supply\s+vessel)\b/gi,
            /\b(cfr|code\s+of\s+federal\s+regulations)\b/gi,
            /\b(abs|american\s+bureau\s+of\s+shipping)\b/gi,
            /\b(solas|safety\s+of\s+life\s+at\s+sea)\b/gi,
            /\b(nvic|navigation\s+and\s+vessel\s+inspection\s+circular)\b/gi,
            /\b(machinery\s+space|accommodation|emergency\s+equipment)\b/gi,
            /\b(drydocking|survey|inspection|certification)\b/gi
        ];

        const terms = [];
        for (const pattern of maritimePatterns) {
            const matches = text.matchAll(pattern);
            for (const match of matches) {
                terms.push(match[0].toLowerCase().replace(/\s+/g, '_'));
            }
        }

        return terms;
    }

    isStopWord(word) {
        const stopWords = new Set([
            'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 
            'by', 'from', 'as', 'is', 'was', 'are', 'were', 'be', 'been', 'have', 
            'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should',
            'may', 'might', 'must', 'shall', 'can', 'this', 'that', 'these', 'those'
        ]);
        return stopWords.has(word);
    }

    calculateRelevanceScore(word, section) {
        let score = 0;
        
        // Higher score for matches in title
        if (section.title.toLowerCase().includes(word)) {
            score += 0.5;
        }
        
        // Higher score for section numbers
        if (section.sectionNumber && section.sectionNumber.includes(word)) {
            score += 0.3;
        }
        
        // Score based on word frequency in content
        const wordCount = (section.content.toLowerCase().match(new RegExp(word, 'g')) || []).length;
        score += Math.min(wordCount * 0.1, 0.8);
        
        // Higher score for shorter sections (more focused content)
        if (section.wordCount < 100) {
            score += 0.2;
        }
        
        return Math.min(score, 1.0);
    }

    async search(query, options = {}) {
        if (!this.initialized) {
            await this.initialize();
        }

        const { maxResults = 10, minRelevanceScore = 0.1, sources = [] } = options;
        const queryWords = this.extractKeywords(query);
        const results = new Map();

        // Find matching sections
        for (const word of queryWords) {
            if (this.searchIndex.has(word)) {
                const matches = this.searchIndex.get(word);
                
                for (const match of matches) {
                    // Apply source filter if specified
                    if (sources.length > 0 && !sources.includes(match.documentId)) {
                        continue;
                    }

                    if (!results.has(match.sectionId)) {
                        results.set(match.sectionId, {
                            ...match,
                            totalScore: 0,
                            matchingWords: []
                        });
                    }
                    
                    const result = results.get(match.sectionId);
                    result.totalScore += match.relevanceScore;
                    result.matchingWords.push(word);
                }
            }
        }

        // Convert to array, filter, and sort
        const sortedResults = Array.from(results.values())
            .filter(result => result.totalScore >= minRelevanceScore)
            .sort((a, b) => b.totalScore - a.totalScore)
            .slice(0, maxResults);

        // Enhance results with full content
        return sortedResults.map(result => ({
            ...result,
            content: this.getFullSectionContent(result.documentId, result.sectionId),
            source: this.getSourceInfo(result.documentId),
            confidence: Math.round(Math.min(result.totalScore * 100, 95))
        }));
    }

    getFullSectionContent(documentId, sectionId) {
        const document = this.documents.get(documentId);
        if (!document) return '';

        const section = document.sections.find(s => s.id === sectionId);
        return section ? section.content : '';
    }

    getSourceInfo(documentId) {
        const sourceMap = {
            'abs_part7': { name: 'ABS', type: 'classification', displayName: 'ABS Part 7' },
            'cfr33': { name: 'CFR33', type: 'federal_regulation', displayName: '33 CFR' },
            'cfr46': { name: 'CFR46', type: 'federal_regulation', displayName: '46 CFR' }
        };
        
        return sourceMap[documentId] || { name: documentId, type: 'unknown', displayName: documentId };
    }

    async addDocument(filePath, documentId) {
        await this.loadDocument(filePath, documentId);
        console.log(`Added document ${documentId} to local search index`);
    }

    getAvailableDocuments() {
        return Array.from(this.documents.values()).map(doc => ({
            id: doc.id,
            title: doc.title,
            sectionCount: doc.sections.length
        }));
    }
}

export default LocalSearchService;