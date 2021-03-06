# -*- coding: utf-8 -*-
module Writexlsx
  module Utility
    ROW_MAX  = 1048576  # :nodoc:
    COL_MAX  = 16384    # :nodoc:
    STR_MAX  = 32767    # :nodoc:
    SHEETNAME_MAX = 31  # :nodoc:

    #
    # xl_rowcol_to_cell($row, col, row_absolute, col_absolute)
    #
    def xl_rowcol_to_cell(row, col, row_absolute = false, col_absolute = false)
      row += 1      # Change from 0-indexed to 1 indexed.
      row_abs = row_absolute ? '$' : ''
      col_abs = col_absolute ? '$' : ''
      col_str = xl_col_to_name(col, col_absolute)
      "#{col_str}#{absolute_char(row_absolute)}#{row}"
    end

    #
    # Returns: [row, col, row_absolute, col_absolute]
    #
    # The row_absolute and col_absolute parameters aren't documented because they
    # mainly used internally and aren't very useful to the user.
    #
    def xl_cell_to_rowcol(cell)
      cell =~ /(\$?)([A-Z]{1,3})(\$?)(\d+)/

      col_abs = $1 != ""
      col     = $2
      row_abs = $3 != ""
      row     = $4.to_i

      # Convert base26 column string to number
      # All your Base are belong to us.
      chars = col.split(//)
      expn = 0
      col = 0

      chars.reverse.each do |char|
        col += (char.ord - 'A'.ord + 1) * (26 ** expn)
        expn += 1
      end

      # Convert 1-index to zero-index
      row -= 1
      col -= 1

      return [row, col, row_abs, col_abs]
    end

    def xl_col_to_name(col, col_absolute)
      # Change from 0-indexed to 1 indexed.
      col += 1
      col_str = ''

      while col > 0
        # Set remainder from 1 .. 26
        remainder = col % 26
        remainder = 26 if remainder == 0

        # Convert the remainder to a character. C-ishly.
        col_letter = ("A".ord + remainder - 1).chr

        # Accumulate the column letters, right to left.
        col_str = col_letter + col_str

        # Get the next order of magnitude.
        col = (col - 1) / 26
      end

      "#{absolute_char(col_absolute)}#{col_str}"
    end

    def xl_range(row_1, row_2, col_1, col_2,
                 row_abs_1 = false, row_abs_2 = false, col_abs_1 = false, col_abs_2 = false)
      range1 = xl_rowcol_to_cell(row_1, col_1, row_abs_1, col_abs_1)
      range2 = xl_rowcol_to_cell(row_2, col_2, row_abs_2, col_abs_2)

      "#{range1}:#{range2}"
    end

    def xl_range_formula(sheetname, row_1, row_2, col_1, col_2)
      # Use Excel's conventions and quote the sheet name if it contains any
      # non-word character or if it isn't already quoted.
      sheetname = "'#{sheetname}'" if sheetname =~ /\W/ && !(sheetname =~ /^'/)

      range1 = xl_rowcol_to_cell( row_1, col_1, 1, 1 )
      range2 = xl_rowcol_to_cell( row_2, col_2, 1, 1 )

      "=#{sheetname}!#{range1}:#{range2}"
    end

    def check_dimensions(row, col)
      if !row || row >= ROW_MAX || !col || col >= COL_MAX
        raise WriteXLSXDimensionError
      end
      0
    end

    #
    # convert_date_time(date_time_string)
    #
    # The function takes a date and time in ISO8601 "yyyy-mm-ddThh:mm:ss.ss" format
    # and converts it to a decimal number representing a valid Excel date.
    #
    # Dates and times in Excel are represented by real numbers. The integer part of
    # the number stores the number of days since the epoch and the fractional part
    # stores the percentage of the day in seconds. The epoch can be either 1900 or
    # 1904.
    #
    # Parameter: Date and time string in one of the following formats:
    #               yyyy-mm-ddThh:mm:ss.ss  # Standard
    #               yyyy-mm-ddT             # Date only
    #                         Thh:mm:ss.ss  # Time only
    #
    # Returns:
    #            A decimal number representing a valid Excel date, or
    #            nil if the date is invalid.
    #
    def convert_date_time(date_time_string)       #:nodoc:
      date_time = date_time_string

      days      = 0 # Number of days since epoch
      seconds   = 0 # Time expressed as fraction of 24h hours in seconds

      # Strip leading and trailing whitespace.
      date_time.sub!(/^\s+/, '')
      date_time.sub!(/\s+$/, '')

      # Check for invalid date char.
      return nil if date_time =~ /[^0-9T:\-\.Z]/

      # Check for "T" after date or before time.
      return nil unless date_time =~ /\dT|T\d/

      # Strip trailing Z in ISO8601 date.
      date_time.sub!(/Z$/, '')

      # Split into date and time.
      date, time = date_time.split(/T/)

      # We allow the time portion of the input DateTime to be optional.
      if time
        # Match hh:mm:ss.sss+ where the seconds are optional
        if time =~ /^(\d\d):(\d\d)(:(\d\d(\.\d+)?))?/
          hour   = $1.to_i
          min    = $2.to_i
          sec    = $4.to_f || 0
        else
          return nil # Not a valid time format.
        end

        # Some boundary checks
        return nil if hour >= 24
        return nil if min  >= 60
        return nil if sec  >= 60

        # Excel expresses seconds as a fraction of the number in 24 hours.
        seconds = (hour * 60* 60 + min * 60 + sec) / (24.0 * 60 * 60)
      end

      # We allow the date portion of the input DateTime to be optional.
      return seconds if date == ''

      # Match date as yyyy-mm-dd.
      if date =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/
        year   = $1.to_i
        month  = $2.to_i
        day    = $3.to_i
      else
        return nil  # Not a valid date format.
      end

      # Set the epoch as 1900 or 1904. Defaults to 1900.
      # Special cases for Excel.
      unless date_1904?
        return      seconds if date == '1899-12-31' # Excel 1900 epoch
        return      seconds if date == '1900-01-00' # Excel 1900 epoch
        return 60 + seconds if date == '1900-02-29' # Excel false leapday
      end


      # We calculate the date by calculating the number of days since the epoch
      # and adjust for the number of leap days. We calculate the number of leap
      # days by normalising the year in relation to the epoch. Thus the year 2000
      # becomes 100 for 4 and 100 year leapdays and 400 for 400 year leapdays.
      #
      epoch   = date_1904? ? 1904 : 1900
      offset  = date_1904? ?    4 :    0
      norm    = 300
      range   = year - epoch

      # Set month days and check for leap year.
      mdays   = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
      leap    = 0
      leap    = 1  if year % 4 == 0 && year % 100 != 0 || year % 400 == 0
      mdays[1]   = 29 if leap != 0

      # Some boundary checks
      return nil if year  < epoch or year  > 9999
      return nil if month < 1     or month > 12
      return nil if day   < 1     or day   > mdays[month - 1]

      # Accumulate the number of days since the epoch.
      days = day                               # Add days for current month
      (0 .. month-2).each do |m|
        days += mdays[m]                      # Add days for past months
      end
      days += range * 365                      # Add days for past years
      days += ((range)                /  4)    # Add leapdays
      days -= ((range + offset)       /100)    # Subtract 100 year leapdays
      days += ((range + offset + norm)/400)    # Add 400 year leapdays
      days -= leap                             # Already counted above

      # Adjust for Excel erroneously treating 1900 as a leap year.
      days += 1 if !date_1904? and days > 59

      date_time = sprintf("%0.10f", days + seconds)
      date_time = date_time.sub(/\.?0+$/, '') if date_time =~ /\./
      if date_time =~ /\./
        date_time.to_f
      else
        date_time.to_i
      end
    end

    def absolute_char(absolute)
      absolute ? '$' : ''
    end

    def xml_str
      @writer.string
    end

    def self.delete_files(path)
      if FileTest.file?(path)
        File.delete(path)
      elsif FileTest.directory?(path)
        Dir.foreach(path) do |file|
          next if file =~ /^\.\.?$/  # '.' or '..'
          delete_files(path.sub(/\/+$/,"") + '/' + file)
        end
        Dir.rmdir(path)
      end
    end

    def put_deprecate_message(method)
      $stderr.puts("Warning: calling deprecated method #{method}. This method will be removed in a future release.")
    end

    # Check for a cell reference in A1 notation and substitute row and column
    def row_col_notation(args)   # :nodoc:
      if args[0] =~ /^\D/
        substitute_cellref(*args)
      else
        args
      end
    end

    #
    # Substitute an Excel cell reference in A1 notation for  zero based row and
    # column values in an argument list.
    #
    # Ex: ("A4", "Hello") is converted to (3, 0, "Hello").
    #
    def substitute_cellref(cell, *args)       #:nodoc:
      return [*args] if cell.respond_to?(:coerce) # Numeric

      cell.upcase!

      case cell
      # Convert a column range: 'A:A' or 'B:G'.
      # A range such as A:A is equivalent to A1:65536, so add rows as required
      when /\$?([A-Z]{1,3}):\$?([A-Z]{1,3})/
        row1, col1 =  xl_cell_to_rowcol($1 + '1')
        row2, col2 =  xl_cell_to_rowcol($2 + ROW_MAX.to_s)
        return [row1, col1, row2, col2, *args]
      # Convert a cell range: 'A1:B7'
      when /\$?([A-Z]{1,3}\$?\d+):\$?([A-Z]{1,3}\$?\d+)/
        row1, col1 =  xl_cell_to_rowcol($1)
        row2, col2 =  xl_cell_to_rowcol($2)
        return [row1, col1, row2, col2, *args]
      # Convert a cell reference: 'A1' or 'AD2000'
      when /\$?([A-Z]{1,3}\$?\d+)/
        row1, col1 =  xl_cell_to_rowcol($1)
        return [row1, col1, *args]
      else
        raise("Unknown cell reference #{cell}")
      end
    end

    def underline_attributes(underline)
      if underline == 2
        ['val', 'double']
      elsif underline == 33
        ['val', 'singleAccounting']
      elsif underline == 34
        ['val', 'doubleAccounting']
      else
        []    # Default to single underline.
      end
    end

    #
    # Write the <color> element.
    #
    def write_color(writer, name, value) #:nodoc:
      attributes = [name, value]

      writer.empty_tag('color', attributes)
    end

    #
    # return perl's boolean result
    #
    def ptrue?(value)
      if [false, nil, 0, "0", "", [], {}].include?(value)
        false
      else
        true
      end
    end

    def check_parameter(params, valid_keys, method)
      invalids = params.keys - valid_keys
      unless invalids.empty?
        raise WriteXLSXOptionParameterError,
          "Unknown parameter '#{invalids.join(', ')}' in #{method}."
      end
      true
    end

    #
    # Check that row and col are valid and store max and min values for use in
    # other methods/elements.
    #
    # The ignore_row/ignore_col flags is used to indicate that we wish to
    # perform the dimension check without storing the value.
    #
    # The ignore flags are use by set_row() and data_validate.
    #
    def check_dimensions_and_update_max_min_values(row, col, ignore_row = 0, ignore_col = 0)       #:nodoc:
      check_dimensions(row, col)
      store_row_max_min_values(row) if ignore_row == 0
      store_col_max_min_values(col) if ignore_col == 0

      0
    end

    def store_row_max_min_values(row)
      @dim_rowmin = row if !@dim_rowmin || (row < @dim_rowmin)
      @dim_rowmax = row if !@dim_rowmax || (row > @dim_rowmax)
    end

    def store_col_max_min_values(col)
      @dim_colmin = col if !@dim_colmin || (col < @dim_colmin)
      @dim_colmax = col if !@dim_colmax || (col > @dim_colmax)
    end
  end
end
