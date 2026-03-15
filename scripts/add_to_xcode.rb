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
# Tìm group phù hợp
# ═══════════════════════════════════════════════════════
wda_lib_group = project.main_group.find_subpath('WebDriverAgentLib', false)
if wda_lib_group.nil?
  wda_lib_group = project.main_group.find_subpath('WebDriverAgentLib/WebDriverAgentLib', false)
end

# FBPhotoCommands → Commands group (cùng chỗ với FBCustomCommands, FBVideoCommands...)
commands_group = nil
routing_group = nil
if wda_lib_group
  commands_group = wda_lib_group.find_subpath('Commands', false)
  routing_group = wda_lib_group.find_subpath('Routing', false)
end

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
# 1. IPCAuthGuard.m → Routing group
# ═══════════════════════════════════════════════════════
auth_group = routing_group || wda_lib_group || project.main_group
puts "Adding IPCAuthGuard.m to group: #{auth_group.display_name}"
add_file_to_target(auth_group, 'IPCAuthGuard.m', lib_target)

# ═══════════════════════════════════════════════════════
# 2. FBPhotoCommands (.h + .m) → Commands group
# ═══════════════════════════════════════════════════════
photo_group = commands_group || wda_lib_group || project.main_group
puts "Adding FBPhotoCommands to group: #{photo_group.display_name}"

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
