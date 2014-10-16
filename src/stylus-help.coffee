
# dependencies

fs = require 'fs'
async = require 'async'
optimist = require 'optimist'
path = require 'path'

filePath = path.join(__dirname, 'valid_selectors.json')
valid_selectors = JSON.parse (fs.readFileSync filePath, 'utf8')

# usage
USAGE = """
Usage: styler <command> [command-specific-options]

where <command> [command-specific-options] is one of:
  alphabetizeStyle <path to stylus dir or file>
  checkAlphabetized <path to stylus dir or file>
  convertStyleToJson <path to stylus dir or file> (note need to > to json write to console)
  inspectZValues <path to stylus dir or file>
  normalizeZvalues <path to stylus dir or file>, [value to normalize on]
  simple_lint <path to stylus dir or file>
"""

# get arguments and options (used for command line executions)
argv = optimist.argv._
command = argv[0]
args = argv[1...argv.length]
opts = optimist.argv

# HELPER FUNCTIONS
exit = (msg) ->
  log msg if msg
  process.exit()

log = (msg) ->
  c = console
  c.log msg

getPreSpaces = (str) ->
  str.match(/^(\s)*/)[0].length

writeToLine = (file, line_str, line_num) ->
  data = fs.readFileSync file,'utf8'
  data = data.split '\n'

  file_str = ''
  for line, index of data
    line = line_str if index is line_num - 1
    end_line = '\n' unless index is data.length - 1
    file_str += "#{line}#{end_line or ''}"
  fs.writeFileSync file, file_str, 'utf8'

alphabetize = (data) ->
  old_data = data.slice(0)
  data.sort()
  arrayEqual = (a, b) ->
    (a.length is b.length) and a.every (elem, i) -> elem is b[i]
  not arrayEqual old_data, data

getFiles = (args, next) ->
  return [] unless args?.length
  stats = fs.statSync args[0]

  if stats.isDirectory()
    read_files = fs.readdirSync args[0]
    for key, val of read_files
      read_files[key] = args[0] + read_files[key]

  else if stats.isFile()
    read_files = [args[0]]

  return read_files

# COMMAND LINE STUFF
processData = (command,args) ->
  read_files = getFiles args

  switch command
    when 'simple_lint'
      config = args[1]
      config ?= {
        bad_indent: 'Bad spacing! should me a multiple of 2 spaces'
        comment_space: '// must have a space after'
        star_selector: '* is HORRIBLE performance please use a different selector'
        zero_px: 'Don\'t need px on 0 values'
        no_colon_semicolon: 'No ; or : in stylus file!'
        comma_space: ', must have a space after'
        alphabetize_check: 'This area needs to be alphabetized'
        dupe_tag_check: 'Duplicate tags found.. please consolidate'
        style_attribute_check: 'Invalid Attribute!'
      }
      errors= []
      addError = (msg, line, line_num) ->
        errors.push {
          message: msg
          line: line
          line_num
        }

      preJsonChecks =  ->
        for file in read_files
          return data_next() unless /.styl/.test(file)
          data = fs.readFileSync file, 'utf8'
          data = data.split '\n'

          for line, line_num in data
            {bad_indent, comment_space, zero_px} = config or {}

            # bad_indent
            if bad_indent
              spaces = getPreSpaces(line)
              if spaces % 2
                addError bad_indent, line, line_num + 1

            # comment_space
            if comment_space
              check_1 = /^\s*\/\//.test line
              check_2 =  /\/\/\s/.test line
              unless check_1 and check_2
                addError comment_space, line, line_num + 1

            # zero_px
            if zero_px
              if /\s0px/.test line
                addError zero_px, line, line_num + 1

      postJsonChecks =  ->
        data = processData 'convertStyleToJson', args
        stylus_stags = []
        total_tags = {}

        config ?= {}
        {star_select, style_attribute_check, no_colon_semicolon} = config
        {comma_space, dupe_tag_check} = config

        for file_name, file of data
          for line_num, attribute_info of file
            continue if attribute_info.tag is ''
            line = parseInt line_num, 10
            total_tags[attribute_info.tag] ?= []
            total_tags[attribute_info.tag].push line - 1

            # star_selector
            if star_selector
              if /\*/.test attribute_info.tag
                addError star_selector, attribute_info.tag, line_num

            for attribute, index in attribute_info.rules
              line_num = line + index - 1

              # invalid attribute check
              if style_attribute_check
                pair = attribute.trim().split ' '
                if pair?.length is 2 and valid_selectors[pair[0]]
                  unless pair[1] in valid_selectors[pair[0]]
                    s_ac = style_attribute_check
                    addError s_ac, attribute, line_num

              # semi colon check
              if no_colon_semicolon
                if /;|:/.test attribute
                  addError no_colon_semicolon, attribute, line_num

              # comma space check
              if comma_space
                check_1 = attribute.match /,/g
                check_2 = attribute.match /,\s/g
                unless check_1?.length is check_2?.length
                  addError comma_space, attribute, line_num

        if dupe_tag_check
          for tag, arr of total_tags
            continue unless arr.length > 1
            for dupe, index in arr
              addError dupe_tag_check, tag, dupe

      alphabetizeCheck = ->
        if config.alphabetize_check
          return_data = processData 'checkAlphabetized', args
          return_data.infractions ?= []
          for infraction, key in return_data.infractions
            {line, line_number} = infraction or {}
            {alphabetize_check} = config or {}
            addError alphabetize_check, line, line_number

      preJsonChecks()
      postJsonChecks()
      alphabetizeCheck()

      return errors

    when 'checkAlphabetized'
      infractions = []
      data = processData 'convertStyleToJson',args
      for file_name, file of data
        for tag, attribute_info of file
          {rules} = attribute_info
          continue unless alphabetize rules
          infractions.push {
            line_number: tag
            line: rules[0]
            file_name
          }

      return {alphabetized: false, infractions} if infractions.length
      return {alphabetized: true}

    when 'alphabetizeStyle'
      data = processData 'convertStyleToJson', args
      for file_name, file of data
        for attribute_info, index in file
          {rules, indent} = attribute_info
          if alphabetize rules
            spaces = Array(indent + 1).join ' '
            for attr, line_num in rules
              line = index + line_num
              writeToLine file_name, "#{spaces}#{attr}", line
      return processData 'checkAlphabetized', args

    when 'convertStyleToJson'

      total_return = {}
      processed = 0

      # a,b  d,c
      # a.d, a.c , b.d, b.c
      join = (data_1, data_2) ->
        arr_1 = data_1.split ','
        arr_2 = data_2.split ','
        str = []
        for arg1 in arr_1
          for arg2 in arr_2
            str.push "#{arg1.trim()} #{arg2.trim()}"
        return str.join(', ')

      for file in read_files
        continue unless /.styl/.test file

        obj = {}
        line_test = ///
          ((\n|^)(\s)*(\.|&|>|\#|@media).+)|(\n|^)(\s)*(table|td|th|tr|div|
          span|a|h1|h2|h3|h4|h5|h6|strong|em|quote|form|fieldset|label|input|
          textarea|button|body|img|ul|li|html|object|iframe|p|blockquote|
          abbr|address|cite|del|dfn|ins|kbd|q|samp|sup|var|b|i|dl|dt|dd|ol|
          legend|caption|tbody|tfoot|thead|article|aside|canvas|details|
          figcaption|figure|footer|header|hgroup|menu|nav|section|summary|
          time|mark|audio|video)(,| |\.|$).*
        ///

        data = fs.readFileSync file, 'utf8'
        data = data.split('\n')
        tagFound = false
        attributeSet = []
        tag = ''
        indent = 0

        for line, line_num of data
          continue if line.match /^\s*$/

          if line.match line_test
            tagFound = true

            if attributeSet.length
              line_number = line_num + 1 - attributeSet.length
              obj[line_number] = {
                indent
                rules: attributeSet
                tag: tag.trim()
              }

            if getPreSpaces line > getPreSpaces tag
              tag = join tag, line.trim()
            else
              tag = line

          else if tagFound
            pre_spaces = getPreSpaces line
            indent = pre_spaces unless indent
            continue unless indent

            if indent is pre_spaces
              attributeSet.push "#{line.trim()}"
            else
              line_number = line_num - attributeSet.length
              obj[line_number] = {
                indent
                rules: attributeSet
                tag: tag.trim()
              }
              tag = ''
              attributeSet = []
              indent = 0

        total_return[file] = obj

      return total_return

    when 'inspectZValues'
      generateJson = (doneJson) ->
        processed = 1
        filesTotal = {}
        for file in read_files
          addFile = (file) ->
            if /.styl/.test file
              data = fs.readFileSync "#{file}",'utf8'
              arr = data.match /(z-index:? +)([0-9]+)/g
              if arr?.length
                for val in arr
                  val = val.match /(z-index:? +)([0-9]+)/
                  z_index = parseInt val[2],10

                  filesTotal[z_index] ?= []
                  filesTotal[z_index].push file

                data_next()

          addFile file

      generateJson filesTotal

    # Normalize z index values
    when 'normalizeZvalues'
      sizeOf = (obj) ->
        size = 0
        size++ for key, val of obj
        return size

      filesTotal = processData 'inspectZValues', args
      count = null
      breathing_room = args[1] or 10
      for z_index, files of filesTotal
        z_index = parseInt z_index,10
        count ?= Math.min z_index,1
        unless z_index is count
          for file in files
            buf = fs.readFileSync "#{file}", 'utf8'
            reg = new RegExp "z-index:? +#{z_index}\n",'g'
            buf = buf.replace reg, "z-index #{count}\n"
            fs.writeFileSync "#{file}", buf, 'utf8'

        count += breathing_room
      filesTotal = processData 'inspectZValues', args
      return filesTotal
    else
      return false

# Support for command line stuff
if /stylus-help/.test module?.parent?.filename
  if value = processData command, args
    value = JSON.stringify value,null,3
    return log value

  log "invalid command #{command}"
  log USAGE

# support for require
exports.processData = processData
