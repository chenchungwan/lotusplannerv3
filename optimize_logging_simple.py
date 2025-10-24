#!/usr/bin/env python3
"""
Simple performance optimization script to replace print statements
"""

import os
import glob

def optimize_file(file_path):
    """Replace print statements with performance-optimized logging"""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    
    # Add import if not present and file has print statements
    if 'import PerformanceLogger' not in content and 'print(' in content:
        # Find the last import statement
        lines = content.split('\n')
        import_index = -1
        for i, line in enumerate(lines):
            if line.strip().startswith('import '):
                import_index = i
        
        if import_index >= 0:
            lines.insert(import_index + 1, 'import PerformanceLogger')
            content = '\n'.join(lines)
    
    # Simple string replacements
    replacements = [
        ('print("🔄 JournalView: Loading drawing for journal page date: \\(currentDate)")', 'logPerformance("Loading drawing for journal page date: \\(currentDate)")'),
        ('print("🔄 JournalView: Loaded existing drawing for date: \\(targetDate)")', 'logPerformance("Loaded existing drawing for date: \\(targetDate)")'),
        ('print("⚠️ JournalView: Date changed during drawing load, ignoring stale data")', 'logWarning("Date changed during drawing load, ignoring stale data")'),
        ('print("🔄 JournalView: No existing drawing found for date: \\(targetDate)")', 'logPerformance("No existing drawing found for date: \\(targetDate)")'),
        ('print("⚠️ JournalView: Save blocked - operation in progress")', 'logWarning("Save blocked - operation in progress")'),
        ('print("💾 JournalView: Starting explicit save to iCloud for \\(currentDate)")', 'logPerformance("Starting explicit save to iCloud for \\(currentDate)")'),
        ('print("💾 JournalView: Saving drawing to iCloud")', 'logPerformance("Saving drawing to iCloud")'),
        ('print("💾 JournalView: Saving photos to iCloud")', 'logPerformance("Saving photos to iCloud")'),
        ('print("✅ JournalView: Successfully saved to iCloud")', 'logInfo("Successfully saved to iCloud")'),
        ('print("❌ JournalView: Failed to save to iCloud: \\(error.localizedDescription)")', 'logError("Failed to save to iCloud: \\(error.localizedDescription)")'),
        ('print("⚠️ JournalView: Load blocked - operation in progress")', 'logWarning("Load blocked - operation in progress")'),
        ('print("📥 JournalView: Loading from iCloud for \\(currentDate)")', 'logPerformance("Loading from iCloud for \\(currentDate)")'),
        ('print("📥 JournalView: Successfully loaded drawing from iCloud")', 'logInfo("Successfully loaded drawing from iCloud")'),
        ('print("📥 JournalView: No drawing found in iCloud")', 'logInfo("No drawing found in iCloud")'),
        ('print("✅ JournalView: Successfully loaded from iCloud")', 'logInfo("Successfully loaded from iCloud")'),
        ('print("❌ JournalView: Failed to load from iCloud: \\(error.localizedDescription)")', 'logError("Failed to load from iCloud: \\(error.localizedDescription)")'),
        ('print("⚠️ JournalView: Date switch blocked - save/load in progress")', 'logWarning("Date switch blocked - save/load in progress")'),
        ('print("🔄 JournalView: Switching to date \\(newDate)")', 'logPerformance("Switching to date \\(newDate)")'),
    ]
    
    for old, new in replacements:
        content = content.replace(old, new)
    
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
