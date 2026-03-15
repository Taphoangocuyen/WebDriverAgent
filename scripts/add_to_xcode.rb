require 'xcodeproj'

project_path = 'WebDriverAgent/WebDriverAgent.xcodeproj'
project = Xcodeproj::Project.open(project_path)

lib_target = project.targets.find { |t| t.name == 'WebDriverAgentLib' }
if lib_target.nil?
  puts "ERROR: WebDriverAgentLib target not found!"
  puts "Available targets: #{project.targets.map(&:name).join(', ')}"
  exit 1
end
puts "Found target: #{lib_target.name}"

# ═══════════════════════════════════════════════════════
# Tìm Commands group (cùng chỗ với FBCustomCommands, FBVideoCommands...)
# ═══════════════════════════════════════════════════════
wda_lib_group = project.main_group.find_subpath('WebDriverAgentLib', false)
if wda_lib_group.nil?
  wda_lib_group = project.main_group.find_subpath('WebDriverAgentLib/WebDriverAgentLib', false)
end

commands_group = nil
if wda_lib_group
  commands_group = wda_lib_group.find_subpath('Commands', false)
end

photo_group = commands_group || wda_lib_group || project.main_group
puts "Adding FBPhotoCommands to group: #{photo_group.display_name}"

# ═══════════════════════════════════════════════════════
# Helper: thêm file vào group + compile sources
# ═══════════════════════════════════════════════════════
def add_file_to_target(group, filename, target)
  existing = group.files.find { |f| f.path == filename }
  if existing
    puts "#{filename} already exists in group, skipping add"
    already_in_sources = target.source_build_phase.files.any? { |bf| bf.file_ref == existing }
    unless already_in_sources
      target.source_build_phase.add_file_reference(existing)
      puts "Added existing #{filename} to compile sources of #{target.name}"
    end
  else
    file_ref = group.new_file(filename)
    puts "Added file reference: #{file_ref.path}"
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added #{filename} to compile sources of #{target.name}"
  end
end

# ═══════════════════════════════════════════════════════
# FBPhotoCommands (.h + .m) → Commands group
# ═══════════════════════════════════════════════════════

# Header file (không cần add to compile sources)
existing_h = photo_group.files.find { |f| f.path == 'FBPhotoCommands.h' }
unless existing_h
  photo_group.new_file('FBPhotoCommands.h')
  puts "Added FBPhotoCommands.h to group"
end

# Implementation file (cần compile)
add_file_to_target(photo_group, 'FBPhotoCommands.m', lib_target)

project.save
puts "Xcode project updated successfully"
