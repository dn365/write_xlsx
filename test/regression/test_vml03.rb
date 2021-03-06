# -*- coding: utf-8 -*-
require 'helper'

class TestRegressionVml03 < Test::Unit::TestCase
  def setup
    setup_dir_var
  end

  def teardown
    File.delete(@xlsx) if File.exist?(@xlsx)
  end

  def test_vml03
    @xlsx = 'vml03.xlsx'
    workbook   = WriteXLSX.new(@xlsx)
    worksheet1 = workbook.add_worksheet
    worksheet2 = workbook.add_worksheet
    worksheet3 = workbook.add_worksheet

    worksheet1.write('A1', 'Foo')
    worksheet1.write_comment('B2',  'Some text')

    worksheet3.write('A1', 'Bar')
    worksheet3.write_comment('C7', 'More text')

    # Set the author to match the target XLSX file.
    worksheet1.set_comments_author('John')
    worksheet3.set_comments_author('John')

    worksheet1.insert_button('C4', {})
    worksheet1.insert_button('E8', {})

    worksheet3.insert_button('B2', {})
    worksheet3.insert_button('C4', {})
    worksheet3.insert_button('E8', {})

    workbook.close
    compare_xlsx_for_regression(File.join(@regression_output, @xlsx), @xlsx)
  end
end
