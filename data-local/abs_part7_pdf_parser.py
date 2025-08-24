#!/usr/bin/env python3
"""
ABS Part 7 PDF Parser for OpenAI Vector Storage
Extracts and structures text from ABS Rules for Survey After Construction Part 7
Optimized for vector search and retrieval.
"""

import fitz  # PyMuPDF
import re
import os
import sys
from typing import List, Dict, Tuple
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class ABSPart7Parser:
    def __init__(self, pdf_path: str):
        self.pdf_path = pdf_path
        self.doc = None
        self.sections = []
        
    def open_pdf(self) -> bool:
        """Open the PDF document."""
        try:
            self.doc = fitz.open(self.pdf_path)
            logger.info(f"Opened PDF: {self.pdf_path} ({len(self.doc)} pages)")
            return True
        except Exception as e:
            logger.error(f"Error opening PDF: {e}")
            return False
    
    def extract_text_from_page(self, page_num: int) -> str:
        """Extract text from a specific page with layout preservation."""
        try:
            page = self.doc[page_num]
            # Extract text with layout information
            text = page.get_text("text")
            return text
        except Exception as e:
            logger.error(f"Error extracting text from page {page_num}: {e}")
            return ""
    
    def clean_text(self, text: str) -> str:
        """Clean and normalize extracted text."""
        # Remove excessive whitespace
        text = re.sub(r'\n\s*\n\s*\n', '\n\n', text)
        text = re.sub(r'[ \t]+', ' ', text)
        
        # Fix hyphenated words that span lines
        text = re.sub(r'(\w+)-\s*\n\s*(\w+)', r'\1\2', text)
        
        # Clean up page breaks and headers/footers
        text = re.sub(r'\n\s*Page \d+.*?\n', '\n', text)
        text = re.sub(r'\n\s*ABS.*?\n', '\n', text)
        text = re.sub(r'\n\s*PART 7.*?\n', '\n', text)
        
        return text.strip()
    
    def identify_sections(self, text: str) -> List[Dict]:
        """Identify and structure sections based on ABS formatting patterns."""
        sections = []
        
        # Common ABS section patterns
        patterns = [
            (r'^CHAPTER (\d+)\s+(.+?)$', 'chapter'),
            (r'^SECTION (\d+)\s+(.+?)$', 'section'),
            (r'^(\d+)\s+(.+?)$', 'main_section'),
            (r'^(\d+\.\d+)\s+(.+?)$', 'subsection'),
            (r'^(\d+\.\d+\.\d+)\s+(.+?)$', 'subsubsection'),
            (r'^([A-Z])\.\s+(.+?)$', 'item'),
            (r'^TABLE (\d+(?:\.\d+)*)\s*[-–]\s*(.+?)$', 'table'),
            (r'^FIGURE (\d+(?:\.\d+)*)\s*[-–]\s*(.+?)$', 'figure'),
        ]
        
        lines = text.split('\n')
        current_section = None
        content_buffer = []
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
                
            # Check if line matches any section pattern
            matched = False
            for pattern, section_type in patterns:
                match = re.match(pattern, line, re.IGNORECASE)
                if match:
                    # Save previous section if exists
                    if current_section and content_buffer:
                        current_section['content'] = '\n'.join(content_buffer).strip()
                        sections.append(current_section)
                    
                    # Start new section
                    if len(match.groups()) >= 2:
                        number, title = match.groups()[:2]
                    else:
                        number, title = match.groups()[0], ""
                    
                    current_section = {
                        'type': section_type,
                        'number': number,
                        'title': title.strip(),
                        'content': '',
                        'full_header': line
                    }
                    content_buffer = []
                    matched = True
                    break
            
            if not matched:
                # Add to current section content
                content_buffer.append(line)
        
        # Don't forget the last section
        if current_section and content_buffer:
            current_section['content'] = '\n'.join(content_buffer).strip()
            sections.append(current_section)
        
        return sections
    
    def format_for_vector_storage(self, sections: List[Dict]) -> str:
        """Format sections as structured markdown for optimal vector storage."""
        markdown_content = []
        
        # Add document header
        markdown_content.append("# ABS Rules for Survey After Construction - Part 7\n")
        markdown_content.append("*American Bureau of Shipping Classification Rules*\n")
        
        for section in sections:
            section_type = section['type']
            number = section['number']
            title = section['title']
            content = section['content']
            
            # Determine heading level based on section type
            if section_type == 'chapter':
                heading = f"# Chapter {number}: {title}"
            elif section_type == 'section':
                heading = f"## Section {number}: {title}"
            elif section_type == 'main_section':
                heading = f"### {number} {title}"
            elif section_type == 'subsection':
                heading = f"#### {number} {title}"
            elif section_type == 'subsubsection':
                heading = f"##### {number} {title}"
            elif section_type == 'table':
                heading = f"### Table {number} - {title}"
            elif section_type == 'figure':
                heading = f"### Figure {number} - {title}"
            elif section_type == 'item':
                heading = f"**{number}.** {title}"
            else:
                heading = f"### {section['full_header']}"
            
            markdown_content.append(f"\n{heading}\n")
            
            if content:
                # Clean up content formatting
                content = self.format_content(content)
                markdown_content.append(f"{content}\n")
        
        return '\n'.join(markdown_content)
    
    def format_content(self, content: str) -> str:
        """Format content text for better readability."""
        # Handle lists and bullet points
        content = re.sub(r'^[-•]\s+', '- ', content, flags=re.MULTILINE)
        content = re.sub(r'^\s*\([a-z]\)\s+', '  - ', content, flags=re.MULTILINE)
        content = re.sub(r'^\s*\d+\)\s+', '  1. ', content, flags=re.MULTILINE)
        
        # Handle regulatory references
        content = re.sub(r'\b(\d+\.\d+\.\d+)\b', r'**\1**', content)
        content = re.sub(r'\b(Section \d+)\b', r'**\1**', content)
        content = re.sub(r'\b(Chapter \d+)\b', r'**\1**', content)
        
        # Handle emphasis for important terms
        content = re.sub(r'\b(shall|must|required|mandatory)\b', r'**\1**', content, flags=re.IGNORECASE)
        content = re.sub(r'\b(may|optional|recommended)\b', r'*\1*', content, flags=re.IGNORECASE)
        
        return content
    
    def extract_table_of_contents(self) -> str:
        """Extract table of contents for navigation."""
        toc_content = []
        
        # Try to extract PDF bookmarks first
        try:
            toc = self.doc.get_toc()
            if toc:
                toc_content.append("## Table of Contents\n")
                for level, title, page in toc:
                    indent = "  " * (level - 1)
                    toc_content.append(f"{indent}- {title} (Page {page})")
                toc_content.append("\n")
        except:
            logger.warning("Could not extract PDF bookmarks")
        
        return '\n'.join(toc_content)
    
    def parse_full_document(self) -> str:
        """Parse the entire PDF document."""
        if not self.open_pdf():
            return ""
        
        logger.info("Starting text extraction...")
        all_text = []
        
        # Extract text from all pages
        for page_num in range(len(self.doc)):
            if page_num % 10 == 0:
                logger.info(f"Processing page {page_num + 1}/{len(self.doc)}")
            
            page_text = self.extract_text_from_page(page_num)
            if page_text:
                cleaned_text = self.clean_text(page_text)
                if cleaned_text:
                    all_text.append(cleaned_text)
        
        # Combine all text
        full_text = '\n\n'.join(all_text)
        logger.info(f"Extracted {len(full_text)} characters of text")
        
        # Identify sections
        logger.info("Identifying document sections...")
        sections = self.identify_sections(full_text)
        logger.info(f"Found {len(sections)} sections")
        
        # Extract table of contents
        toc = self.extract_table_of_contents()
        
        # Format for vector storage
        logger.info("Formatting for vector storage...")
        formatted_content = self.format_for_vector_storage(sections)
        
        # Combine TOC and content
        final_content = toc + formatted_content
        
        self.doc.close()
        return final_content
    
    def save_to_file(self, content: str, output_path: str):
        """Save formatted content to file."""
        try:
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(content)
            logger.info(f"Saved formatted content to: {output_path}")
            logger.info(f"File size: {len(content)} characters")
        except Exception as e:
            logger.error(f"Error saving file: {e}")

def main():
    # Configuration
    pdf_path = "/Users/dp/Downloads/part-7-july20.pdf"
    output_path = "/Users/dp/Downloads/ABS-Part-7-Structured.md"
    
    # Check if PDF exists
    if not os.path.exists(pdf_path):
        print(f"Error: PDF file not found at {pdf_path}")
        sys.exit(1)
    
    # Initialize parser
    parser = ABSPart7Parser(pdf_path)
    
    # Parse document
    print("Starting ABS Part 7 PDF parsing...")
    print("This may take several minutes for large documents...")
    
    formatted_content = parser.parse_full_document()
    
    if formatted_content:
        # Save to file
        parser.save_to_file(formatted_content, output_path)
        
        # Print summary
        print(f"\n✅ Successfully processed ABS Part 7 PDF!")
        print(f"📄 Input: {pdf_path}")
        print(f"📝 Output: {output_path}")
        print(f"📊 Content size: {len(formatted_content):,} characters")
        print(f"\n🔍 Recommended chunk size for OpenAI vector storage: 1500-2000 tokens")
        print(f"📋 The document is now structured with proper headings for optimal search")
    else:
        print("❌ Failed to process PDF")
        sys.exit(1)

if __name__ == "__main__":
    main()