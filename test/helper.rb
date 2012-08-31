# -*- coding: utf-8 -*-
require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'test/unit'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'write_xlsx'

class Writexlsx::Workbook
  #
  # Set the default index for each format. This is mainly used for testing.
  #
  def set_default_xf_indices #:nodoc:
    @formats.each { |format| format.get_xf_index }
  end
end

class Test::Unit::TestCase
  require 'rexml/document'
  include REXML

  def setup_dir_var
    @test_dir = File.dirname(__FILE__)
    @expected_dir = File.join(@test_dir, 'expected_dir')
    @result_dir   = File.join(@test_dir, 'result_dir')
    @perl_output  = File.join(@test_dir, 'perl_output')
  end

  def expected_to_array(lines)
    array = []
    lines.each_line do |line|
      str = line.chomp.sub(%r!/>$!, ' />').sub(/^\s+/, '')
      array << str unless str == ''
    end
    array
  end

  def got_to_array(xml_str)
    str = xml_str.gsub(/[\r\n]/, '')
    str.gsub(/>[ \t\r\n]*</, ">\t<").split(/\t/)
  end

  def compare_xlsx(expected, result, xlsx)
    begin
      prepare_compare(expected, result, xlsx)
      expected_files = files(expected)
      result_files   = files(result)

      not_exists = expected_files - result_files
      assert(not_exists.empty?, "These files does not exist: #{not_exists.to_s}")

      additional_exist = result_files - expected_files
      assert(additional_exist.empty?, "These files must not exist: #{additional_exist.to_s}")

      compare_files(expected, result)
    ensure
      cleanup(xlsx)
    end
  end

  def compare_files(expected, result)
    files(expected).each do |file|
      compare_file(expected, result, file)
    end
  end

  def compare_file(expected, result, file)
    expected_doc = ""
    result_doc   = ""
    Document.new(IO.read(File.join(expected, file))).write(expected_doc, 1)
    Document.new(IO.read(File.join(result,   file))).write(result_doc,   1)

    assert_equal(expected_doc.gsub(/\r/, ''), result_doc.gsub(/\r/, ''), "#{file} differs.")
  end

  def prepare_compare(expected, result, xlsx)
    prepare_xlsx(expected, File.join(@perl_output, xlsx))
    prepare_xlsx(result, xlsx)
  end

  def prepare_xlsx(dir, xlsx)
    Dir.mkdir(dir)
    system("unzip -q #{xlsx} -d #{dir}")
    remove_dates_user_specific_data_from_core_xml(dir)
    remove_printer_settings_from_pagesetup_elements(dir)
  end

  def remove_dates_user_specific_data_from_core_xml(dir)
    filename = File.join(dir, "docProps/core.xml")
    return unless File.exist?(filename)

    xml = IO.read(filename)
    xml.gsub!(/John/, '')
    xml.gsub!(/\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ/, '')
    open(filename, "w") {|f| f.write(xml)}
  end

  def remove_printer_settings_from_pagesetup_elements(dir)

  end

  def files(dir)
    Dir.glob(File.join(dir, "**/*")).select { |f| File.file?(f) }.
                                     reject { |f| File.basename(f) =~ /(core|theme1)\.xml/ }.
                                     collect { |f| f.sub(Regexp.new("^#{dir}"), '') }
  end

  def cleanup(xlsx)
    Writexlsx::Utility.delete_files(xlsx)          if File.exist?(xlsx)
    Writexlsx::Utility.delete_files(@expected_dir) if File.exist?(@expected_dir)
    Writexlsx::Utility.delete_files(@result_dir)   if File.exist?(@result_dir)
  end
end
