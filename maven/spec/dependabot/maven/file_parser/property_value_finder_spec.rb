# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/maven/file_parser/property_value_finder"

RSpec.describe Dependabot::Maven::FileParser::PropertyValueFinder do
  let(:finder) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [base_pom] }
  let(:base_pom) do
    Dependabot::DependencyFile.new(
      name: "pom.xml",
      content: fixture("poms", base_pom_fixture_name)
    )
  end
  let(:base_pom_fixture_name) { "property_pom.xml" }

  describe "#property_details" do
    subject(:property_details) do
      finder.property_details(
        property_name: property_name,
        callsite_pom: callsite_pom
      )
    end

    context "when the property is declared in the calling pom" do
      let(:base_pom_fixture_name) { "property_pom.xml" }
      let(:property_name) { "springframework.version" }
      let(:callsite_pom) { base_pom }
      its([:value]) { is_expected.to eq("4.3.12.RELEASE") }

      context "and the property is an attribute on the project" do
        let(:base_pom_fixture_name) { "project_version_pom.xml" }
        let(:property_name) { "project.version" }
        its([:value]) { is_expected.to eq("0.0.2-RELEASE") }
      end

      context "and the property is within a profile" do
        let(:base_pom_fixture_name) { "profile_property_pom.xml" }
        its([:value]) { is_expected.to eq("4.3.12.RELEASE") }
      end

      context "when the property contains a tricky to split string" do
        let(:property_name) { "accumulo.1.6.version" }
        specify { expect { property_details }.to_not raise_error }
      end
    end

    context "when the property is declared in a parent pom" do
      let(:dependency_files) { [base_pom, child_pom, grandchild_pom] }
      let(:child_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/pom.xml",
          content: fixture("poms", "legacy_pom.xml")
        )
      end
      let(:grandchild_pom) do
        Dependabot::DependencyFile.new(
          name: "legacy/some-spring-project/pom.xml",
          content: fixture("poms", "some_spring_project_pom.xml")
        )
      end

      let(:base_pom_fixture_name) { "multimodule_pom.xml" }
      let(:property_name) { "spring.version" }
      let(:callsite_pom) { grandchild_pom }
      its([:value]) { is_expected.to eq("2.5.6") }

      context "and the property name needs careful manipulation" do
        let(:property_name) { "spring.version.2.2" }
        its([:value]) { is_expected.to eq("2.2.1") }

        context "(case2)" do
          let(:property_name) { "jta-api-1.2-version" }
          its([:value]) { is_expected.to eq("1.2.1") }
        end
      end
    end

    context "when the property is declared in a remote pom" do
      let(:base_pom_fixture_name) { "remote_parent_pom.xml" }
      let(:property_name) { "log4j2.version" }
      let(:callsite_pom) { base_pom }

      let(:struts_apps_maven_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/apache/struts/struts2-apps/2.5.10/struts2-apps-2.5.10.pom"
      end
      let(:struts_parent_maven_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/apache/struts/struts2-parent/2.5.10/struts2-parent-2.5.10.pom"
      end
      let(:struts_apps_maven_response) do
        fixture("poms", "struts2-apps-2.5.10.pom")
      end
      let(:struts_parent_maven_response) do
        fixture("poms", "struts2-parent-2.5.10.pom")
      end

      before do
        stub_request(:get, struts_apps_maven_url).
          to_return(status: 200, body: struts_apps_maven_response)
        stub_request(:get, struts_parent_maven_url).
          to_return(status: 200, body: struts_parent_maven_response)
      end
      its([:value]) { is_expected.to eq("2.7") }

      context "that can't be found" do
        before do
          stub_request(:get, struts_apps_maven_url).
            to_return(status: 404, body: "")
        end

        it { is_expected.to be_nil }
      end

      context "that specifies a version range (so can't be fetched)" do
        let(:base_pom_fixture_name) { "remote_parent_pom_with_range.xml" }
        it { is_expected.to be_nil }
      end

      context "that uses properties so can't be fetched" do
        let(:base_pom_fixture_name) { "remote_parent_pom_with_props.xml" }
        it { is_expected.to be_nil }
      end

      context "that is a custom repo" do
        let(:base_pom_fixture_name) { "custom_repositories_child_pom.xml" }

        let(:scala_plugins_maven_url) do
          "https://repo.maven.apache.org/maven2/" \
            "org/scala-tools/maven-scala-plugin/2.15.2/" \
            "maven-scala-plugin-2.15.2.pom"
        end
        let(:scala_plugins_jboss_url) do
          "http://child-repository.jboss.org/maven2/" \
            "org/scala-tools/maven-scala-plugin/2.15.2/" \
            "maven-scala-plugin-2.15.2.pom"
        end
        let(:scala_plugins_jboss_response) do
          fixture("poms", "struts2-parent-2.5.10.pom")
        end

        before do
          stub_request(:get, scala_plugins_maven_url).
            to_return(status: 404, body: "")
          stub_request(:get, scala_plugins_jboss_url).
            to_return(status: 200, body: scala_plugins_jboss_response)
        end

        its([:value]) { is_expected.to eq("2.7") }
      end
    end

    context "with a pom that contains invalid xml" do
      let(:dependency_files) { project_dependency_files("invalid_version_ref") }
      let(:property_name) { "guava.version`" }
      let(:callsite_pom) { dependency_files.find { |f| f.name == "pom.xml" } }

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::DependencyFileNotEvaluatable) do |error|
          expect(error.message).to eq("ERROR: Invalid expression: /project/guava.version`")
        end
      end
    end
  end
end
