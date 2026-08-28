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
puts "Adding custom command files to group: #{photo_group.display_name}"

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
# Lệnh tuỳ biến của repo này (.h + .m) → Commands group
#   FBPhotoCommands — /wda/importPhoto, /wda/importVideo
#   FBPasteCommands — /wda/paste, /wda/setClipboard
# ═══════════════════════════════════════════════════════
%w[FBPhotoCommands FBPasteCommands].each do |base|
  # Header: chỉ cần nằm trong group, KHÔNG đưa vào compile sources
  unless photo_group.files.find { |f| f.path == "#{base}.h" }
    photo_group.new_file("#{base}.h")
    puts "Added #{base}.h to group"
  end

  # Implementation: phải compile
  add_file_to_target(photo_group, "#{base}.m", lib_target)
end


# ════════════════════════════════════════
# Photos.framework → target WebDriverAgentLib
# ════════════════════════════════════════
# Trước đây việc này do scripts/link_photos_framework.py làm bằng regex trên
# project.pbxproj. Hai chỗ yếu của cách đó:
#   - Chỉ kiểm chuỗi "Photos.framework" có xuất hiện ở BẤT KỲ đâu trong file
#     rồi bỏ qua. Nếu upstream nhắc tới nó ở target khác thì WebDriverAgentLib
#     không bao giờ được link.
#   - Khi thêm thì thêm vào MỌI frameworks build phase khớp regex, không riêng
#     WebDriverAgentLib.
# Ở đây đã có đối tượng target thật nên link thẳng, và kiểm cũng thẳng.
already_linked = lib_target.frameworks_build_phase.files.any? do |bf|
  bf.file_ref && bf.file_ref.path.to_s.end_with?('Photos.framework')
end

if already_linked
  puts "Photos.framework already linked to #{lib_target.name}, skipping"
else
  photos_ref = project.frameworks_group.files.find { |f| f.path.to_s.end_with?('Photos.framework') }
  if photos_ref.nil?
    photos_ref = project.frameworks_group.new_file('System/Library/Frameworks/Photos.framework')
    photos_ref.source_tree = 'SDKROOT'
    puts "Created file reference: #{photos_ref.path}"
  end
  lib_target.frameworks_build_phase.add_file_reference(photos_ref)
  puts "Linked Photos.framework to #{lib_target.name}"
end

# Kiểm lại từ chính cây đối tượng — nếu hụt thì dừng NGAY ở bước tạo project,
# đỡ phải chờ build xong mới biết ở bước verify.
linked_now = lib_target.frameworks_build_phase.files.any? do |bf|
  bf.file_ref && bf.file_ref.path.to_s.end_with?('Photos.framework')
end
unless linked_now
  puts "ERROR: Photos.framework vẫn chưa nằm trong frameworks build phase của #{lib_target.name}"
  exit 1
end

# Kiểm cả hai .m có THẬT trong compile sources không. Cùng lý do với đoạn kiểm
# Photos.framework ở trên: hụt một file thì build vẫn xanh, IPA vẫn chạy, chỉ
# thiếu mất route — và chỉ lòi ra ở bước verify sau ~15 phút chờ.
%w[FBPhotoCommands.m FBPasteCommands.m].each do |m|
  compiled = lib_target.source_build_phase.files.any? do |bf|
    bf.file_ref && bf.file_ref.path.to_s.end_with?(m)
  end
  next if compiled

  puts "ERROR: #{m} khong nam trong compile sources cua #{lib_target.name}"
  exit 1
end

project.save
puts "Xcode project updated successfully"
