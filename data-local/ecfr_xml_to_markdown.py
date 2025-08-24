#!/usr/bin/env python3
"""
ECFR XML to Markdown Converter

This script converts Electronic Code of Federal Regulations (ECFR) XML files
to clean, well-formatted Markdown optimized for vector search and retrieval.

Usage:
    python ecfr_xml_to_markdown.py

The script will process ECFR-title33.xml and ECFR-title46.xml files in the
current directory and output corresponding .md files.
"""

import xml.etree.ElementTree as ET
import re
import os
import sys
from pathlib import Path
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class ECFRToMarkdownConverter:
    """Converts ECFR XML files to structured Markdown format."""
    
    def __init__(self):
        # Define heading levels for different XML elements
        self.heading_levels = {
            'TITLE': 1,
            'CHAPTER': 2,
            'SUBCHAP': 3,
            'PART': 4,
            'SUBPART': 5,
            'SECTION': 6
        }
        
        # Track current context for better formatting
        self.current_context = {
            'title': '',
            'chapter': '',
            'part': '',
            'subpart': '',
            'section': ''
        }
    
    def clean_text(self, text):
        """Clean and normalize text content."""
        if not text:
            return ""
        
        # Remove excessive whitespace and normalize line breaks
        text = re.sub(r'\s+', ' ', text.strip())
        
        # Fix common formatting issues
        text = re.sub(r'\s+([.,:;!?])', r'\1', text)  # Remove space before punctuation
        text = re.sub(r'([.!?])\s*([A-Z])', r'\1 \2', text)  # Ensure space after sentence end
        
        return text
    
    def extract_text_content(self, element):
        """Extract all text content from an element and its children."""
        content = []
        
        if element.text:
            content.append(element.text)
        
        for child in element:
            if child.tag == 'E':  # Emphasis element
                emphasis_type = child.get('T', '03')  # Default to italic
                text_content = self.extract_text_content(child)
                if emphasis_type in ['03', '04']:  # Italic
                    content.append(f"*{text_content}*")
                elif emphasis_type in ['01', '02']:  # Bold
                    content.append(f"**{text_content}**")
                else:
                    content.append(text_content)
            elif child.tag == 'I':  # Italic
                content.append(f"*{self.extract_text_content(child)}*")
            elif child.tag == 'SU':  # Superscript
                content.append(f"^{self.extract_text_content(child)}^")
            elif child.tag == 'SB':  # Subscript
                content.append(f"_{self.extract_text_content(child)}_")
            else:
                content.append(self.extract_text_content(child))
            
            if child.tail:
                content.append(child.tail)
        
        return self.clean_text(''.join(content))
    
    def get_heading_level(self, div_type):
        """Determine the appropriate heading level for a division type."""
        return self.heading_levels.get(div_type, 6)
    
    def format_section_number(self, section_num):
        """Format section numbers consistently."""
        if section_num.startswith('§'):
            return section_num
        elif section_num.replace('.', '').replace('-', '').isdigit():
            return f"§ {section_num}"
        else:
            return section_num
    
    def process_division(self, div_element, level=1):
        """Process a division element and return formatted markdown."""
        content = []
        div_type = div_element.get('TYPE', '').upper()
        div_number = div_element.get('N', '')
        
        # Extract heading
        head_element = div_element.find('HEAD')
        if head_element is not None:
            heading_text = self.extract_text_content(head_element)
            heading_level = min(self.get_heading_level(div_type), 6)
            
            # Update context based on division type
            if div_type == 'TITLE':
                self.current_context['title'] = heading_text
            elif div_type == 'CHAPTER':
                self.current_context['chapter'] = heading_text
            elif div_type == 'PART':
                self.current_context['part'] = heading_text
            elif div_type == 'SUBPART':
                self.current_context['subpart'] = heading_text
            elif div_type == 'SECTION':
                self.current_context['section'] = heading_text
                heading_text = self.format_section_number(heading_text)
            
            # Create markdown heading
            heading_prefix = '#' * heading_level
            content.append(f"\n{heading_prefix} {heading_text}\n")
        
        # Process authority section
        auth_element = div_element.find('AUTH')
        if auth_element is not None:
            content.append(self.process_authority(auth_element))
        
        # Process source section
        source_element = div_element.find('SOURCE')
        if source_element is not None:
            content.append(self.process_source(source_element))
        
        # Process editorial notes
        ednote_element = div_element.find('EDNOTE')
        if ednote_element is not None:
            content.append(self.process_editorial_note(ednote_element))
        
        # Process direct child paragraphs only
        for p_element in div_element.findall('P'):
            content.append(self.process_paragraph(p_element))
        
        # Process child divisions recursively
        for child_div in div_element:
            if child_div.tag.startswith('DIV') and child_div.tag != div_element.tag:
                content.append(self.process_division(child_div, level + 1))
        
        return '\n'.join(content)
    
    def process_paragraph(self, p_element):
        """Process a paragraph element."""
        text = self.extract_text_content(p_element)
        if text:
            return f"\n{text}\n"
        return ""
    
    def process_authority(self, auth_element):
        """Process authority section."""
        content = []
        
        hed_element = auth_element.find('HED')
        if hed_element is not None:
            content.append(f"\n**{self.extract_text_content(hed_element)}**")
        
        pspace_element = auth_element.find('PSPACE')
        if pspace_element is not None:
            content.append(f"{self.extract_text_content(pspace_element)}\n")
        
        return '\n'.join(content)
    
    def process_source(self, source_element):
        """Process source section."""
        content = []
        
        hed_element = source_element.find('HED')
        if hed_element is not None:
            content.append(f"\n**{self.extract_text_content(hed_element)}**")
        
        pspace_element = source_element.find('PSPACE')
        if pspace_element is not None:
            content.append(f"{self.extract_text_content(pspace_element)}\n")
        
        return '\n'.join(content)
    
    def process_editorial_note(self, ednote_element):
        """Process editorial note section."""
        content = []
        
        hed_element = ednote_element.find('HED')
        if hed_element is not None:
            content.append(f"\n**{self.extract_text_content(hed_element)}**")
        
        for child in ednote_element:
            if child.tag == 'PSPACE':
                content.append(f"{self.extract_text_content(child)}")
            elif child.tag == 'P':
                content.append(f"{self.extract_text_content(child)}")
        
        if content:
            content.append("")  # Add blank line after editorial note
        
        return '\n'.join(content)
    
    def process_citation(self, cita_element):
        """Process citation elements."""
        text = self.extract_text_content(cita_element)
        if text:
            return f"\n*{text}*\n"
        return ""
    
    def extract_metadata(self, root):
        """Extract document metadata."""
        metadata = {}
        
        # Extract title
        title_element = root.find('.//TITLE')
        if title_element is not None:
            metadata['title'] = self.extract_text_content(title_element)
        
        # Extract title number
        idno_element = root.find('.//IDNO[@TYPE="title"]')
        if idno_element is not None:
            metadata['title_number'] = self.extract_text_content(idno_element)
        
        # Extract amendment date
        amddate_element = root.find('.//AMDDATE')
        if amddate_element is not None:
            metadata['amendment_date'] = self.extract_text_content(amddate_element)
        
        return metadata
    
    def convert_file(self, input_file, output_file):
        """Convert a single ECFR XML file to Markdown."""
        logger.info(f"Converting {input_file} to {output_file}")
        
        try:
            # Parse XML file
            tree = ET.parse(input_file)
            root = tree.getroot()
            
            # Extract metadata
            metadata = self.extract_metadata(root)
            
            # Start building markdown content
            content = []
            
            # Add title and metadata
            if 'title' in metadata:
                content.append(f"# {metadata['title']}")
                content.append("")
            
            if 'title_number' in metadata:
                content.append(f"**Title:** {metadata['title_number']}")
            
            if 'amendment_date' in metadata:
                content.append(f"**Last Updated:** {metadata['amendment_date']}")
            
            content.append("")
            content.append("---")
            content.append("")
            
            # Process main content divisions
            for div1 in root.findall('.//DIV1'):
                content.append(self.process_division(div1))
            
            # Process any remaining top-level sections
            for section in root.findall('.//DIV8[@TYPE="SECTION"]'):
                # Check if this section is already processed as part of DIV1
                already_processed = False
                for div1 in root.findall('.//DIV1'):
                    if section in div1.iter():
                        already_processed = True
                        break
                if not already_processed:
                    content.append(self.process_section(section))
            
            # Write to output file
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write('\n'.join(content))
            
            logger.info(f"Successfully converted {input_file}")
            
        except ET.ParseError as e:
            logger.error(f"XML parsing error in {input_file}: {e}")
            raise
        except Exception as e:
            logger.error(f"Error processing {input_file}: {e}")
            raise
    
    def process_section(self, section_element):
        """Process a section element specifically."""
        content = []
        
        # Process heading
        head_element = section_element.find('HEAD')
        if head_element is not None:
            heading_text = self.extract_text_content(head_element)
            heading_text = self.format_section_number(heading_text)
            content.append(f"\n###### {heading_text}\n")
        
        # Process paragraphs
        for p_element in section_element.findall('P'):
            content.append(self.process_paragraph(p_element))
        
        # Process citations
        for cita_element in section_element.findall('CITA'):
            content.append(self.process_citation(cita_element))
        
        return '\n'.join(content)

def main():
    """Main function to convert ECFR XML files to Markdown."""
    converter = ECFRToMarkdownConverter()
    
    # Define input and output files
    files_to_convert = [
        ('ECFR-title33.xml', 'ECFR-title33.md'),
        ('ECFR-title46.xml', 'ECFR-title46.md')
    ]
    
    # Check if input files exist
    missing_files = []
    for input_file, _ in files_to_convert:
        if not os.path.exists(input_file):
            missing_files.append(input_file)
    
    if missing_files:
        logger.error(f"Missing input files: {', '.join(missing_files)}")
        logger.info("Please ensure the XML files are in the current directory.")
        return 1
    
    # Convert files
    success_count = 0
    for input_file, output_file in files_to_convert:
        try:
            converter.convert_file(input_file, output_file)
            success_count += 1
            
            # Display file statistics
            input_size = os.path.getsize(input_file) / (1024 * 1024)  # MB
            output_size = os.path.getsize(output_file) / (1024 * 1024)  # MB
            logger.info(f"File sizes - Input: {input_size:.1f}MB, Output: {output_size:.1f}MB")
            
        except Exception as e:
            logger.error(f"Failed to convert {input_file}: {e}")
    
    if success_count == len(files_to_convert):
        logger.info("All files converted successfully!")
        logger.info("Markdown files are optimized for vector search and retrieval.")
        return 0
    else:
        logger.error(f"Converted {success_count}/{len(files_to_convert)} files successfully.")
        return 1

if __name__ == "__main__":
    sys.exit(main())