require 'fileutils'

# MeetingFileUtils: Utilities for meeting-related file and directory operations
#
# Provides helper methods for common file and directory tasks in the meeting workflow.
module MeetingFileUtils
  # Creates required subfolders if they don't exist.
  #
  # target_dir - The String path to the notes directory.
  #
  # Returns nothing.
  def self.ensure_subfolders(target_dir:)
    %w[Executive\ Summaries Meeting\ Notes Transcripts Weekly\ Notes].each do |subdir|
      path = File.join(target_dir, subdir)
      FileUtils.mkdir_p(path) unless Dir.exist?(path)
    end
  end

  # Finds transcript and chat log files in a given folder.
  #
  # folder - The String path to the meeting folder.
  #
  # Returns an Array of String file paths.
  def self.find_transcript_files(folder:)
    Dir[File.join(folder, '*.{txt,vtt}')]
  end

  # Prepares and returns the output directory for transcripts for a given date.
  #
  # transcripts_base - The String base path for transcripts.
  # meeting_date     - The String date (YYYY-MM-DD).
  #
  # Returns the String path to the created directory.
  def self.prepare_transcript_dir(transcripts_base:, meeting_date:)
    dest_dir = File.join(transcripts_base, meeting_date)
    FileUtils.mkdir_p(dest_dir)
    dest_dir
  end

  # Finds the next available transcript filename in a directory.
  #
  # dest_dir - The String path to the transcript directory.
  #
  # Returns the String filename for the next available transcript.
  def self.next_transcript_filename(dest_dir:)
    counter = 1
    loop do
      filename = "#{counter.to_s.rjust(2, '0')}.md"
      return filename unless File.exist?(File.join(dest_dir, filename))
      counter += 1
    end
  end

  # Updates or creates a Meeting Notes file for a given group/person/section, including detailed notes.
  #
  # meeting_notes_file - The String path to the Meeting Notes file.
  # meeting_date       - The String date (YYYY-MM-DD).
  # transcript_link    - The String wikilink to the transcript.
  # summary_link       - The String wikilink to the executive summary.
  # detailed_notes     - The String output from the LLM for detailed notes (should be list items, or will be split into them).
  # filename           - The String filename (without extension) for the note.
  #
  # If the file exists and a section for this date exists, appends the new links and detailed notes to that section.
  # Otherwise, prepends a new section for the date at the top.
  #
  # Returns nothing.
  def self.update_meeting_notes_file_with_details(meeting_notes_file:, meeting_date:, transcript_link:, summary_link:, detailed_notes:, filename:)
    date_section_header = "## #{meeting_date}"
    # Ensure detailed_notes is a string of list items (one per line, starting with '-')
    # Preserve indentation by only removing trailing whitespace
    detailed_notes_items = detailed_notes.lines.map(&:rstrip).reject(&:empty?).map { |line| line.lstrip.start_with?("-") ? line : "- #{line}" }.join("\n")
    new_content_block = "- #{transcript_link}\n- #{summary_link}\n" + (detailed_notes_items.empty? ? "" : "#{detailed_notes_items}\n") + "\n"
    if File.exist?(meeting_notes_file)
      content = File.read(meeting_notes_file)
      # Regex to find all date sections
      sections = content.split(/^(## \d{4}-\d{2}-\d{2})/)
      # sections[0] is preamble (likely empty), then alternating header, body, header, body...
      found = false
      new_content = sections.each_slice(2).map do |header, body|
        if header == date_section_header
          found = true
          # Append new links and detailed notes to the end of this date section's body
          header + (body || "") + new_content_block
        elsif header
          header + (body || "")
        else
          header.to_s
        end
      end.join("")
      unless found
        # Prepend new date section to the top
        new_content = date_section_header + "\n" + new_content_block + content
      end
      File.write(meeting_notes_file, new_content)
    else
      # Create new file with date section
      File.write(meeting_notes_file, "# Meeting Notes\n\n" + date_section_header + "\n" + new_content_block)
    end
  end
end