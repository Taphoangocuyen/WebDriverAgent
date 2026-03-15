#!/usr/bin/env python3
"""
Patch project.pbxproj to add Photos.framework to WebDriverAgentLib.
Required for FBPhotoCommands (PHPhotoLibrary API).
"""
import re
import sys
import os

def find_pbxproj(wda_dir):
    path = os.path.join(wda_dir, "WebDriverAgent.xcodeproj", "project.pbxproj")
    return path if os.path.exists(path) else None

def patch_pbxproj(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    if 'Photos.framework' in content:
        print("Photos.framework already in project, skipping")
        return

    # ── Step 1: Add PBXFileReference for Photos.framework ──
    # Find an existing system framework reference to use as template
    # Pattern: XXXXXXXX /* SomeFramework.framework */ = {isa = PBXFileReference; ...
    fw_ref_pattern = r'([A-F0-9]{24}) /\* \w+\.framework \*/ = \{isa = PBXFileReference; lastKnownFileType = wrapper\.framework; name = \w+\.framework; path = System/Library/Frameworks/\w+\.framework; sourceTree = SDKROOT; \};'

    fw_match = re.search(fw_ref_pattern, content)
    if not fw_match:
        # Fallback: simpler pattern
        fw_ref_pattern = r'([A-F0-9]{24}) /\* \w+\.framework \*/ = \{isa = PBXFileReference;[^}]+sourceTree = SDKROOT; \};'
        fw_match = re.search(fw_ref_pattern, content)

    if not fw_match:
        print("WARNING: Could not find framework reference pattern, using OTHER_LDFLAGS fallback")
        # Fallback: add -framework Photos to OTHER_LDFLAGS
        content = content.replace(
            'OTHER_LDFLAGS = (',
            'OTHER_LDFLAGS = (\n\t\t\t\t\t"-framework",\n\t\t\t\t\tPhotos,',
            1  # Only first occurrence
        )
        with open(filepath, 'w') as f:
            f.write(content)
        print("OK: Added Photos to OTHER_LDFLAGS")
        return

    # Generate unique IDs (24 hex chars)
    import hashlib
    base = hashlib.sha256(b"PhotosFrameworkRef").hexdigest()[:24].upper()
    file_ref_id = base
    build_file_id = hashlib.sha256(b"PhotosBuildFile").hexdigest()[:24].upper()

    # Add file reference
    new_file_ref = f'\t\t{file_ref_id} /* Photos.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Photos.framework; path = System/Library/Frameworks/Photos.framework; sourceTree = SDKROOT; }};\n'

    # Insert after the matched framework reference line
    insert_pos = fw_match.end() + 1
    content = content[:insert_pos] + new_file_ref + content[insert_pos:]

    # ── Step 2: Add PBXBuildFile ──
    # Find existing build file for a framework
    bf_pattern = r'([A-F0-9]{24}) /\* \w+\.framework in Frameworks \*/ = \{isa = PBXBuildFile; fileRef = [A-F0-9]{24} /\* \w+\.framework \*/; \};'
    bf_match = re.search(bf_pattern, content)

    if bf_match:
        new_build_file = f'\t\t{build_file_id} /* Photos.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* Photos.framework */; }};\n'
        bf_insert_pos = bf_match.end() + 1
        content = content[:bf_insert_pos] + new_build_file + content[bf_insert_pos:]

        # ── Step 3: Add to WebDriverAgentLib's frameworks build phase ──
        # Find the frameworks phase that contains other .framework refs for WebDriverAgentLib
        phase_pattern = r'(files = \([^)]*?/\* \w+\.framework in Frameworks \*/[^)]*?\))'

        def add_to_phase(match):
            original = match.group(0)
            if 'Photos.framework' in original:
                return original
            # Add before closing paren
            insertion = f'\t\t\t\t{build_file_id} /* Photos.framework in Frameworks */,\n'
            return original.replace('\t\t\t);', insertion + '\t\t\t);', 1)

        content = re.sub(phase_pattern, add_to_phase, content, count=0, flags=re.DOTALL)

    with open(filepath, 'w') as f:
        f.write(content)

    print(f"OK: Added Photos.framework to {filepath}")
    print(f"  FileRef: {file_ref_id}")
    print(f"  BuildFile: {build_file_id}")

if __name__ == '__main__':
    wda_dir = sys.argv[1] if len(sys.argv) > 1 else "WebDriverAgent"
    pbxproj = find_pbxproj(wda_dir)
    if not pbxproj:
        print(f"ERROR: project.pbxproj not found in {wda_dir}")
        sys.exit(1)
    patch_pbxproj(pbxproj)
