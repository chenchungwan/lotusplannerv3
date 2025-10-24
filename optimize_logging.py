#!/usr/bin/env python3
"""
Performance optimization script to replace print statements with high-performance logging
"""

import os
import re
import glob

def optimize_file(file_path):
    """Replace print statements with performance-optimized logging"""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    
    # Add import if not present
    if 'import PerformanceLogger' not in content and 'print(' in content:
        # Find the last import statement
        import_pattern = r'(import\s+[^\n]+\n)'
        imports = re.findall(import_pattern, content)
        if imports:
            last_import = imports[-1]
            content = content.replace(last_import, last_import + 'import PerformanceLogger\n')
    
    # Replace common print patterns with performance logging
    replacements = [
        # JournalView patterns
        (r'print\("🔄 JournalView: Loading drawing for journal page date: \(currentDate\)"\)', 'logPerformance("Loading drawing for journal page date: \\(currentDate)")'),
        (r'print\("🔄 JournalView: Loaded existing drawing for date: \(targetDate\)"\)', 'logPerformance("Loaded existing drawing for date: \\(targetDate)")'),
        (r'print\("⚠️ JournalView: Date changed during drawing load, ignoring stale data"\)', 'logWarning("Date changed during drawing load, ignoring stale data")'),
        (r'print\("🔄 JournalView: No existing drawing found for date: \(targetDate\)"\)', 'logPerformance("No existing drawing found for date: \\(targetDate)")'),
        (r'print\("⚠️ JournalView: Save blocked - operation in progress"\)', 'logWarning("Save blocked - operation in progress")'),
        (r'print\("💾 JournalView: Starting explicit save to iCloud for \(currentDate\)"\)', 'logPerformance("Starting explicit save to iCloud for \\(currentDate)")'),
        (r'print\("💾 JournalView: Saving drawing to iCloud"\)', 'logPerformance("Saving drawing to iCloud")'),
        (r'print\("💾 JournalView: Saving photos to iCloud"\)', 'logPerformance("Saving photos to iCloud")'),
        (r'print\("✅ JournalView: Successfully saved to iCloud"\)', 'logInfo("Successfully saved to iCloud")'),
        (r'print\("❌ JournalView: Failed to save to iCloud: \(error\.localizedDescription\)"\)', 'logError("Failed to save to iCloud: \\(error.localizedDescription)")'),
        
        # General patterns
        (r'print\("⚠️.*"\)', 'logWarning("\\1")'),
        (r'print\("❌.*"\)', 'logError("\\1")'),
        (r'print\("✅.*"\)', 'logInfo("\\1")'),
        (r'print\("🔄.*"\)', 'logPerformance("\\1")'),
        (r'print\("📸.*"\)', 'logPerformance("\\1")'),
        (r'print\("💾.*"\)', 'logPerformance("\\1")'),
        (r'print\("📥.*"\)', 'logPerformance("\\1")'),
    ]
    
    for pattern, replacement in replacements:
        content = re.sub(pattern, replacement, content)
    
    # Only write if content changed
    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Optimized: {file_path}")
        return True
    
    return False

def main():
    """Main optimization function"""
    
    # Find all Swift files
    swift_files = glob.glob('LotusPlannerV3/LotusPlannerV3/**/*.swift', recursive=True)
    
    optimized_count = 0
    
    for file_path in swift_files:
        if optimize_file(file_path):
            optimized_count += 1
    
    print(f"Optimized {optimized_count} files")

if __name__ == '__main__':
    main()
