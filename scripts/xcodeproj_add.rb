#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Add source/resource files to the Meridian Xcode target, registering them in
# project.pbxproj with the correct group hierarchy and build phase.
#
# Usage:
#   ruby scripts/xcodeproj_add.rb <project.xcodeproj> <Target> <relpath> [relpath...]
#
# Paths are relative to the inner source root (the folder containing AppDelegate.swift),
# e.g.  Panel/Daybreak/DaybreakView.swift
#
# Idempotent: a file already referenced in its group is skipped. Groups are created
# as needed. .swift -> Compile Sources; .xcstrings/.strings/.png/etc -> Resources
# (routed automatically by xcodeproj based on file type).

gem 'xcodeproj'
require 'xcodeproj'

project_path = ARGV[0]
target_name  = ARGV[1]
rel_files    = ARGV[2..-1] || []

abort "usage: xcodeproj_add.rb <project> <target> <file...>" if project_path.nil? || target_name.nil? || rel_files.empty?

project = Xcodeproj::Project.open(project_path)
target  = project.targets.find { |t| t.name == target_name }
abort "target not found: #{target_name}" if target.nil?

root = project.main_group # anchors the inner source folder

# Find (or create) a nested group by walking path components from `root`.
def group_for_dir(root, dir)
  group = root
  return group if dir.nil? || dir.empty? || dir == '.'
  dir.split('/').reject { |c| c.empty? || c == '.' }.each do |comp|
    existing = group.children.find do |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) &&
        (c.display_name == comp || c.path == comp || c.name == comp)
    end
    group = existing || group.new_group(comp, comp) # name + path both = comp (folder-backed)
  end
  group
end

added = []
skipped = []

rel_files.each do |rel|
  rel = rel.sub(%r{\A\./}, '')
  dir = File.dirname(rel)
  base = File.basename(rel)
  group = group_for_dir(root, dir)

  already = group.files.find { |f| f.display_name == base || f.path == base }
  if already
    # Ensure it is in the target's build phase even if the ref pre-existed.
    in_target = target.source_build_phase.files_references.include?(already) ||
                (target.resources_build_phase && target.resources_build_phase.files_references.include?(already))
    target.add_file_references([already]) unless in_target
    skipped << rel
    next
  end

  ref = group.new_reference(base) # path = base, sourceTree = <group>
  target.add_file_references([ref])
  added << "#{rel}  ->  #{ref.real_path}"
end

project.save

puts "ADDED (#{added.size}):"
added.each { |a| puts "  + #{a}" }
puts "SKIPPED already-present (#{skipped.size}):"
skipped.each { |s| puts "  = #{s}" }
