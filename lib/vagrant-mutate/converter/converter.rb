require 'fileutils'

module VagrantMutate
  module Converter
    class Converter

      def self.create(env, input_box, output_box)
        case output_box.provider_name
        when 'kvm'
          require_relative 'kvm'
          Kvm.new(env, input_box, output_box)
        when 'libvirt'
          require_relative 'libvirt'
          Libvirt.new(env, input_box, output_box)
        else
          raise Errors::ProviderNotSupported, :provider => output_box.provider_name, :direction => 'output'
        end
      end

      def initialize(env, input_box, output_box)
        @env = env
        @input_box  = input_box
        @output_box = output_box
        @logger = Log4r::Logger.new('vagrant::mutate')
        verify_qemu_installed
        verify_qemu_version
      end

      def convert()
        @env.ui.info "Converting #{@input_box.name} from #{@input_box.provider_name} "\
          "to #{@output_box.provider_name}."

        write_metadata
        copy_vagrantfile
        write_specific_files
        write_disk
      end

      private

      # http://stackoverflow.com/questions/2108727/which-in-ruby-checking-if-program-exists-in-path-from-ruby
      def verify_qemu_installed
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
        ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
          exts.each do |ext|
            exe = File.join(path, "qemu-img#{ext}")
            if File.executable? exe
              @logger.info "Found qemu"
              return
            end
          end
        end
        # if we make it here qemu-img command was not found
        raise Errors::QemuNotFound
      end

      def verify_qemu_version
        usage = `qemu-img`
        if usage =~ /(\d+\.\d+\.\d+)/
          recommended_version = Gem::Version.new('1.2.0')
          installed_version = Gem::Version.new($1)
          if installed_version < recommended_version
            @env.ui.warn "You have qemu #{installed_version} installed. "\
              "This version is too old to read some virtualbox boxes. "\
              "If conversion fails, try upgrading to qemu 1.2.0 or newer."
          end
        else
          raise Errors::ParseQemuVersionFailed
        end
      end


      def write_metadata
        metadata = generate_metadata
        begin
          File.open( File.join( @output_box.dir, 'metadata.json'), 'w') do |f|
            f.write( JSON.generate(metadata) )
          end
        rescue => e
          raise Errors::WriteMetadataFailed, :error_message => e.message
        end
        @logger.info "Wrote metadata"
      end

      def copy_vagrantfile
        input = File.join( @input_box.dir, 'Vagrantfile' )
        if File.exists? input
          output = File.join( @output_box.dir, 'Vagrantfile' )
          @logger.info "Copying #{input} to #{output}"
          begin
            FileUtils.copy_file(input, output)
          rescue => e
            raise Errors::WriteVagrantfileFailed, :error_message => e.message
          end
        end
      end

      def write_disk
        if @input_box.image_format == @output_box.image_format
          copy_disk
        else
          convert_disk
        end
      end

      def copy_disk
        input = File.join( @input_box.dir, @input_box.image_name )
        output = File.join( @output_box.dir, @output_box.image_name )
        @logger.info "Copying #{input} to #{output}"
        begin
          FileUtils.copy_file(input, output)
        rescue => e
          raise Errors::WriteDiskFailed, :error_message => e.message
        end
      end

      def convert_disk
        input_file    = File.join( @input_box.dir, @input_box.image_name )
        output_file   = File.join( @output_box.dir, @output_box.image_name )
        input_format  = @input_box.image_format
        output_format = @output_box.image_format

        # p for progress bar
        # S for sparse file
        # c for compress(supporeted by qcow/qcow2)
        qemu_options = '-p -S 16k'
        qemu_options += ' -c' if output_format == 'qcow2'

        command = "qemu-img convert #{qemu_options} -f #{input_format} -O #{output_format} #{input_file} #{output_file}"
        @logger.info "Running #{command}"
        unless system(command)
          raise Errors::WriteDiskFailed, :error_message => "qemu-img exited with status #{$?.exitstatus}"
        end
      end

    end
  end
end
