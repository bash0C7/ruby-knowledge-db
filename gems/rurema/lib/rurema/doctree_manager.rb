require 'open3'

module Rurema
  class DoctreeManager
    RUREMA_REPO = 'https://github.com/rurema/doctree.git'

    def initialize(doctree_path)
      @doctree_path = File.expand_path(doctree_path)
    end

    def sync
      if Dir.exist?(File.join(@doctree_path, '.git'))
        git_pull
      else
        git_clone
      end
    end

    def rd_files(_version)
      src_dir = File.join(@doctree_path, 'refm', 'api', 'src')
      Dir.glob(File.join(src_dir, '**', '*.rd')).sort
    end

    private

    def git_clone
      out, status = Open3.capture2e('git', 'clone', '--depth=1', RUREMA_REPO, @doctree_path)
      raise "git clone failed: #{out}" unless status.success?
    end

    def git_pull
      out, status = Open3.capture2e('git', '-C', @doctree_path, 'pull', '--ff-only')
      raise "git pull failed: #{out}" unless status.success?
    end
  end
end
