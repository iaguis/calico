require "jekyll"
require "tempfile"
require_relative "./lib"

# This plugin enables jekyll to render helm charts.
# Traditionally, Jekyll will render files which make use of the Liquid templating language.
# This plugin adds a new 'tag' that when specified will pass the input to the Helm binary.
# example use:
#
# {% helm %}
# datastore: kubernetes
# networking: calico
# {% endhelm %}
module Jekyll
  class RenderHelmTagBlock < Liquid::Block
    def initialize(tag_name, extra_args, liquid_options)
      super
      if not extra_args.empty?
        @extra_args = extra_args
      end
    end
    def render(context)
      text = super

      # Because helm hasn't merged stdin support, write the passed-in values.yaml
      # to a tempfile on disk.
      t = Tempfile.new("jhelm")
      t.write(text)
      t.close

      version = context.registers[:page]["version"]
      imageRegistry = context.registers[:page]["registry"]
      imageNames = context.registers[:site].config["imageNames"]
      versions = context.registers[:site].data["versions"]

      # If versions.yml doesn't contain component version info for the requested version,
      # only log a warning if 'ignoreMissingVersions' is set 'true' in their _config.yaml.
      @ignoreMissingVersions = context.registers[:site].config["ignoreMissingVersions"]
      begin
        vs = parse_versions(versions, version)
      rescue IndexError
        if !@ignoreMissingVersions
          raise
        else
          puts "ignoring missing version '#{version}'"
          return
        end
      end

      versionsYml = gen_values(vs, imageNames, imageRegistry)

      tv = Tempfile.new("temp_versions.yml")
      tv.write(versionsYml)
      tv.close

      # Execute helm.
      # Set the default etcd endpoint placeholder for rendering in the docs.
      cmd = """helm template _includes/#{version}/charts/calico \
        -f #{tv.path} \
        -f #{t.path}
        --set etcd.endpoints=http://<ETCD_IP>:<ETCD_PORT>"""

      if @extra_args
        cmd += " " + @extra_args
      end

      out = `#{cmd}`

      t.unlink
      tv.unlink
      return out
    end
  end
end

Liquid::Template.register_tag('helm', Jekyll::RenderHelmTagBlock)
