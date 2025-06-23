require "spec_helper"

RSpec.describe Soloist::CLI do
  let(:cli) { Soloist::CLI.new }
  let(:base_path) { RSpec.configuration.tempdir }
  let(:soloistrc_path) { File.expand_path("soloistrc", base_path) }
  let(:system_commands) { [] }

  before do
    FileUtils.mkdir_p(base_path)
    # Setup method spies that still allow actual execution
    allow_any_instance_of(Soloist::Config).to receive(:exec)
    allow_any_instance_of(Soloist::Config).to receive(:run_chef).and_call_original
    allow_any_instance_of(Soloist::Config).to receive(:chef_solo).and_call_original
    # Let chef_cache_path execute, but we've mocked the system call it uses
    allow_any_instance_of(Soloist::Config).to receive(:chef_cache_path).and_call_original
    # Mock the system call for cache path creation
    allow_any_instance_of(Soloist::Config).to receive(:conditional_sudo).and_call_original
    # This avoids actual sudo execution
    allow_any_instance_of(Kernel).to receive(:system) { |_, c|
      system_commands << c
    }
  end

  describe "#chef" do
    it "receives the outside environment" do
      FileUtils.touch(soloistrc_path)
      Dir.chdir(base_path) do
        ENV["AUTRYITIS"] = "yodelmania"
        allow(cli.soloist_config).to receive(:chef_solo).and_return('echo $AUTRYITIS')
        cli.chef
        expect(cli.soloist_config)
          .to have_received(:exec).with(a_string_including('echo $AUTRYITIS'))
      end
    end

    context "when the soloistrc file does not exist" do
      it "raises an error" do
        expect do
          begin
            Dir.chdir(base_path) { cli.chef }
          rescue Soloist::NotFound => e
            expect(e.message).to eq("Could not find soloistrc or .soloistrc")
            raise
          end
        end.to raise_error(Soloist::NotFound)
      end
    end

    context "when the soloistrc file exists" do
      before do
        File.open(soloistrc_path, "w") do |file|
          file.write(YAML.dump("recipes" => ["stinky::feet"]))
        end
        cli.soloist_config = nil
        Dir.chdir(base_path) { allow(cli.soloist_config).to receive(:exec) }
      end

      it "runs the proper recipes" do
        cli.chef
        expect(cli.soloist_config.royal_crown.recipes).to match_array(["stinky::feet"])
      end

      context "when a soloistrc_local file exists" do
        let(:soloistrc_local_path) { File.expand_path("soloistrc_local", base_path) }

        before do
          File.open(soloistrc_local_path, "w") do |file|
            file.write(YAML.dump("recipes" => ["stinky::socks"]))
          end
          cli.soloist_config = nil
          Dir.chdir(base_path) { allow(cli.soloist_config).to receive(:exec) }
        end

        it "installs the proper recipes" do
          cli.chef
          expect(cli.soloist_config.royal_crown.recipes).to match_array(["stinky::feet", "stinky::socks"])
        end
      end

      context "when the Berksfile does not exist" do
        it "runs chef" do
          cli.chef
          expect(cli.soloist_config).to have_received(:exec).at_least(:once)
            expect(cli.soloist_config)
              .to have_received(:exec).with(a_string_including('chef-solo -c'))
        end

        it "does not run berkshelf" do
          expect_any_instance_of(Berkshelf::Berksfile).to_not receive(:install)
          cli.chef
        end
      end

      context "when the Berksfile exists" do
        let(:berksfile) { double("Berksfile") }

        before do
          FileUtils.touch(File.expand_path("Berksfile", base_path))
          system_commands.clear
        end

        it "runs berkshelf" do
          expect(Berkshelf::Berksfile).to receive(:from_file).with('Berksfile').and_return(berksfile)
          expect(berksfile).to receive(:install)
          expect(berksfile).to receive(:vendor).with(File.expand_path('cookbooks', File.realpath(base_path)))
          cli.chef
        end

        context "when the user is not root" do
          before do
            system_commands.clear
            allow(Process).to receive(:uid).and_return(1000) # Simulate a non-root user
            allow(File).to receive(:directory?).and_call_original
            allow(File).to receive(:directory?).with('/var/chef/cache').and_return(false)
          end
          it "creates the cache path using sudo" do
            cli.chef
            expect(cli.soloist_config)
              .to have_received(:conditional_sudo).with('mkdir -p /var/chef/cache')
            expect(system_commands).to include('sudo -E mkdir -p /var/chef/cache')
            expect(cli.soloist_config)
              .to have_received(:exec).with(a_string_including('sudo -E'))
          end
        end

        context "when the user is root" do
          before do
            system_commands.clear
            allow(Process).to receive(:uid).and_return(0)
            allow(File).to receive(:directory?).and_call_original
            allow(File).to receive(:directory?).with('/var/chef/cache').and_return(false)
          end

          it "does not use sudo but still creates cache path" do
            commands = []
            allow(cli.soloist_config).to receive(:exec) { |c| commands << c }
            cli.chef
            expect(commands).to_not include(a_string_including("sudo -E"))
            expect(system_commands).to include("mkdir -p /var/chef/cache")
            expect(system_commands).not_to include(a_string_including("sudo -E"))
          end
        end
      end
    end
  end

  describe "#run_recipe" do
    context "when the soloistrc does not exist" do
      it "raises an error" do
        expect do
          Dir.chdir(base_path) { cli.run_recipe("pineapple::wut") }
        end.to raise_error(Soloist::NotFound)
      end
    end

    context "when the soloistrc file exists" do
      before do
        File.open(soloistrc_path, "w") do |file|
          file.write(YAML.dump("recipes" => ["pineapple::wutcake"]))
        end
      end

      it "sets a recipe to run" do
        Dir.chdir(base_path) do
          expect(cli).to receive(:chef)
          cli.run_recipe("angst::teenage", "ennui::default")
          expect(cli.soloist_config.royal_crown.recipes).to match_array(["angst::teenage", "ennui::default"])
        end
      end
    end
  end

  describe "#config" do
    let(:royal_crown) { Soloist::RoyalCrown.new(:node_attributes => {"a" => "b"}) }
    let(:config) { Soloist::Config.new(royal_crown) }

    before { allow(cli).to receive(:soloist_config).and_return(config) }

    it "prints the hash render of the RoyalCrown" do
      expect(Kernel).to receive(:ap).with({"recipes"=>[], "a" => "b"})
      cli.config
    end
  end
end
