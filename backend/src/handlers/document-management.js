import fs from 'node:fs/promises';
import path from 'node:path';
import LocalSearchService from '../services/local-search.js';

const localSearchService = new LocalSearchService();

/**
 * Document Management System for adding new regulation documents
 */
export class DocumentManager {
    constructor() {
        this.documentsPath = path.join(process.cwd(), '..', 'data-local');
        this.supportedTypes = ['md', 'txt', 'pdf'];
        this.maxFileSize = 50 * 1024 * 1024; // 50MB
    }

    async fileExists(filePath) {
        try {
            await fs.access(filePath);
            return true;
        } catch {
            return false;
        }
    }

    /**
     * Add a new document to the local search index
     */
    async addDocument(fileBuffer, fileName, documentType, metadata = {}) {
        try {
            // Validate file
            this.validateFile(fileBuffer, fileName, documentType);

            // Generate unique document ID
            const timestamp = Date.now();
            const baseName = path.parse(fileName).name;
            const documentId = `${documentType}_${baseName}_${timestamp}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');
            
            // Determine file extension and content
            const extension = path.parse(fileName).ext.toLowerCase();
            let content = '';
            let processedFileName = '';

            if (extension === '.md' || extension === '.txt') {
                content = fileBuffer.toString('utf8');
                processedFileName = `${documentId}.md`;
            } else if (extension === '.pdf') {
                // For now, save PDF and require manual conversion
                processedFileName = `${documentId}.pdf`;
                content = await this.extractPDFContent(fileBuffer, fileName);
            } else {
                throw new Error(`Unsupported file type: ${extension}`);
            }

            // Save file to documents directory
            const filePath = path.join(this.documentsPath, processedFileName);
            
            if (extension === '.pdf') {
                await fs.writeFile(filePath, fileBuffer);
                // Also save extracted content as markdown
                const mdPath = path.join(this.documentsPath, `${documentId}.md`);
                await fs.writeFile(mdPath, content, 'utf8');
            } else {
                await fs.writeFile(filePath, content, 'utf8');
            }

            // Add to search index
            await localSearchService.addDocument(
                extension === '.pdf' ? path.join(this.documentsPath, `${documentId}.md`) : filePath,
                documentId
            );

            // Save metadata
            const metadataPath = path.join(this.documentsPath, `${documentId}.meta.json`);
            const fullMetadata = {
                id: documentId,
                originalName: fileName,
                type: documentType,
                addedDate: new Date().toISOString(),
                fileSize: fileBuffer.length,
                extension: extension,
                ...metadata
            };
            
            await fs.writeFile(metadataPath, JSON.stringify(fullMetadata, null, 2));

            return {
                success: true,
                documentId: documentId,
                message: `Successfully added ${fileName} to local search index`,
                metadata: fullMetadata
            };

        } catch (error) {
            console.error('Document addition error:', error);
            throw error;
        }
    }

    /**
     * Remove a document from the search index
     */
    async removeDocument(documentId) {
        try {
            const files = [
                path.join(this.documentsPath, `${documentId}.md`),
                path.join(this.documentsPath, `${documentId}.pdf`),
                path.join(this.documentsPath, `${documentId}.txt`),
                path.join(this.documentsPath, `${documentId}.meta.json`)
            ];

            let removed = false;
            for (const file of files) {
                if (await this.fileExists(file)) {
                    try {
                        await fs.unlink(file);
                        removed = true;
                    } catch (err) {
                        console.warn(`Failed to remove ${file}:`, err);
                    }
                }
            }

            if (!removed) {
                throw new Error(`Document ${documentId} not found`);
            }

            // Reinitialize search service to reflect changes
            await localSearchService.initialize();

            return {
                success: true,
                message: `Document ${documentId} removed successfully`
            };

        } catch (error) {
            console.error('Document removal error:', error);
            throw error;
        }
    }

    /**
     * List all available documents
     */
    async listDocuments() {
        try {
            const files = await fs.readdir(this.documentsPath);
            const metaFiles = files.filter(f => f.endsWith('.meta.json'));
            
            const documents = [];
            for (const metaFile of metaFiles) {
                try {
                    const metaPath = path.join(this.documentsPath, metaFile);
                    const metadata = JSON.parse(await fs.readFile(metaPath, 'utf8'));
                    documents.push(metadata);
                } catch (error) {
                    console.warn(`Failed to read metadata for ${metaFile}:`, error);
                }
            }

            // Sort by added date (newest first)
            documents.sort((a, b) => new Date(b.addedDate) - new Date(a.addedDate));

            return {
                success: true,
                documents: documents,
                totalCount: documents.length
            };

        } catch (error) {
            console.error('Document listing error:', error);
            throw error;
        }
    }

    /**
     * Get document content
     */
    async getDocument(documentId) {
        try {
            const metaPath = path.join(this.documentsPath, `${documentId}.meta.json`);
            if (!await this.fileExists(metaPath)) {
                throw new Error(`Document ${documentId} not found`);
            }

            const metadata = JSON.parse(await fs.readFile(metaPath, 'utf8'));
            
            // Try to read content file
            const possibleFiles = [
                path.join(this.documentsPath, `${documentId}.md`),
                path.join(this.documentsPath, `${documentId}.txt`)
            ];

            let content = '';
            for (const file of possibleFiles) {
                if (await this.fileExists(file)) {
                    content = await fs.readFile(file, 'utf8');
                    break;
                }
            }

            return {
                success: true,
                metadata: metadata,
                content: content,
                wordCount: content.split(/\s+/).length
            };

        } catch (error) {
            console.error('Document retrieval error:', error);
            throw error;
        }
    }

    /**
     * Validate uploaded file
     */
    validateFile(fileBuffer, fileName, documentType) {
        // Check file size
        if (fileBuffer.length > this.maxFileSize) {
            throw new Error(`File size exceeds maximum of ${this.maxFileSize / (1024 * 1024)}MB`);
        }

        // Check file extension
        const extension = path.parse(fileName).ext.toLowerCase().substring(1);
        if (!this.supportedTypes.includes(extension)) {
            throw new Error(`Unsupported file type. Supported types: ${this.supportedTypes.join(', ')}`);
        }

        // Validate document type
        const validTypes = ['solas', 'nvic', 'uscg', 'imo', 'custom', 'cfr33', 'cfr46', 'abs'];
        if (!validTypes.includes(documentType.toLowerCase())) {
            throw new Error(`Invalid document type. Valid types: ${validTypes.join(', ')}`);
        }

        // Basic content validation for text files
        if (extension === 'md' || extension === 'txt') {
            const content = fileBuffer.toString('utf8');
            if (content.length < 100) {
                throw new Error('Document content too short (minimum 100 characters)');
            }
        }
    }

    /**
     * Extract content from PDF (placeholder - would need actual PDF parsing)
     */
    async extractPDFContent(fileBuffer, fileName) {
        // This is a placeholder for PDF content extraction
        // In production, you would use a library like pdf-parse or pdf2pic
        
        return `# ${fileName}\n\n` +
               `## Content Extraction Notice\n\n` +
               `This PDF document (${fileName}) has been uploaded to the ArrowReg system. ` +
               `To enable full-text search capabilities, please:\n\n` +
               `1. Extract the text content from the PDF\n` +
               `2. Format it as Markdown with proper headings and sections\n` +
               `3. Replace this placeholder content\n\n` +
               `**File Information:**\n` +
               `- Original filename: ${fileName}\n` +
               `- File size: ${(fileBuffer.length / 1024).toFixed(2)} KB\n` +
               `- Upload date: ${new Date().toISOString()}\n\n` +
               `**Note:** This document is currently not searchable. Please process the content manually for full functionality.`;
    }

    /**
     * Bulk import documents from a directory
     */
    async bulkImport(importPath, documentType) {
        try {
            if (!await this.fileExists(importPath)) {
                throw new Error(`Import path does not exist: ${importPath}`);
            }

            const files = (await fs.readdir(importPath))
                .filter(f => {
                    const ext = path.parse(f).ext.toLowerCase().substring(1);
                    return this.supportedTypes.includes(ext);
                });

            const results = [];
            let successCount = 0;
            let errorCount = 0;

            for (const fileName of files) {
                try {
                    const filePath = path.join(importPath, fileName);
                    const fileBuffer = await fs.readFile(filePath);
                    
                    const result = await this.addDocument(fileBuffer, fileName, documentType);
                    results.push(result);
                    successCount++;
                    
                } catch (error) {
                    results.push({
                        success: false,
                        fileName: fileName,
                        error: error.message
                    });
                    errorCount++;
                }
            }

            return {
                success: true,
                message: `Bulk import completed: ${successCount} successful, ${errorCount} errors`,
                totalFiles: files.length,
                successCount: successCount,
                errorCount: errorCount,
                results: results
            };

        } catch (error) {
            console.error('Bulk import error:', error);
            throw error;
        }
    }
}

/**
 * HTTP handlers for document management
 */
export async function handleDocumentUpload(request) {
    try {
        const formData = await request.formData();
        const file = formData.get('file');
        const documentType = formData.get('type') || 'custom';
        const metadata = {};

        // Extract optional metadata
        const title = formData.get('title');
        const description = formData.get('description');
        const source = formData.get('source');
        
        if (title) metadata.title = title;
        if (description) metadata.description = description;
        if (source) metadata.source = source;

        if (!file) {
            throw new Error('No file provided');
        }

        const fileBuffer = await file.arrayBuffer();
        const manager = new DocumentManager();
        
        const result = await manager.addDocument(
            Buffer.from(fileBuffer),
            file.name,
            documentType,
            metadata
        );

        return new Response(JSON.stringify(result), {
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        });

    } catch (error) {
        console.error('Document upload error:', error);
        return new Response(JSON.stringify({
            success: false,
            error: error.message
        }), {
            status: 400,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        });
    }
}

export async function handleDocumentList(request) {
    try {
        const manager = new DocumentManager();
        const result = await manager.listDocuments();

        return new Response(JSON.stringify(result), {
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        });

    } catch (error) {
        console.error('Document list error:', error);
        return new Response(JSON.stringify({
            success: false,
            error: error.message
        }), {
            status: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        });
    }
}

export async function handleDocumentDelete(request) {
    try {
        const { documentId } = await request.json();
        
        if (!documentId) {
            throw new Error('Document ID is required');
        }

        const manager = new DocumentManager();
        const result = await manager.removeDocument(documentId);

        return new Response(JSON.stringify(result), {
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        });

    } catch (error) {
        console.error('Document delete error:', error);
        return new Response(JSON.stringify({
            success: false,
            error: error.message
        }), {
            status: 400,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        });
    }
}