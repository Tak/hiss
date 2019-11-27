require 'gtk3'
require 'base64'

module Hiss
  class UI
    BUFFER_SIZE = 8192

    def initialize
      @builder = Gtk::Builder.new()
      @builder.add_from_file('ui.glade')
      @builder.connect_signals{ |handler| method(handler) }
      @builder['mainWindow'].show_all()

      # Hide result UI until we actually do something
      @builder['frameResultsText'].hide()
      @builder['boxReconstructTextSecret'].hide()
      @builder['frameResultsFile'].hide()
      @builder['frameReconstructFileResults'].hide()
    end

    def ui_validate_text
      secret = @builder['entrySecretText'].text
      totalPieces = @builder['spinnerTotalPiecesText'].value
      requiredPieces = @builder['spinnerRequiredPiecesText'].value
      @builder['buttonGenerateText'].sensitive = !secret.empty? && totalPieces >= requiredPieces
      UI.clear_grid(@builder['gridResultText'])
    end

    def get_selectable_label(text, horizontal_alignment)
      label = Gtk::Label.new(text)
      label.selectable = true
      label.xalign = horizontal_alignment
      return label
    end

    def self.clear_grid(grid)
      while (grid.get_child_at(0, 0))
        grid.remove_row(0)
      end
    end

    def ui_generate_text
      secret = @builder['entrySecretText'].text
      totalPieces = @builder['spinnerTotalPiecesText'].value
      requiredPieces = @builder['spinnerRequiredPiecesText'].value

      pieces, prime = Hiss.new(secret, totalPieces, requiredPieces).generate()
      @builder['labelPrimeText'].text = prime.to_s()
      grid = @builder['gridResultText']
      UI.clear_grid(grid)
      pieces.each_with_index do |piece, index|
        grid.insert_row(index)
        grid.attach(get_selectable_label(piece[0].to_s(), 1.0), 0, index, 1, 1)
        grid.attach(get_selectable_label(Base64.urlsafe_encode64(piece[1]), 0.25), 1, index, 1, 1)
      end
      @builder['frameResultsText'].show_all()
    end

    def self.get_index_entry
      entry = Gtk::Entry.new()
      entry.placeholder_text = 'Index'
      entry.input_purpose = Gtk::InputPurpose::DIGITS
      return entry
    end

    def self.get_piece_entry
      entry = Gtk::Entry.new()
      entry.placeholder_text = 'Secret shard'
      return entry
    end

    def ui_text_reconstruct_pieces_count_changed
      grid = @builder['gridReconstructTextPieces']
      UI.clear_grid(grid)
      pieces = @builder['spinnerReconstructTextPieces'].value
      (1..pieces).each do |index|
        grid.insert_row(index - 1)
        grid.attach(UI.get_index_entry(), 0, index - 1, 1, 1)
        grid.attach(UI.get_piece_entry(), 1, index - 1, 1, 1)
      end
      grid.show_all()
      ui_validate_reconstruct_text()
    end

    def ui_validate_reconstruct_text
      button = @builder['buttonReconstructText']
      prime_string = @builder['entryReconstructTextPrimeModulator'].text.strip()
      valid = (prime_string.to_i() != 0)
      if !valid
        button.sensitive = false
        return
      end

      grid = @builder['gridReconstructTextPieces']
      pieces = @builder['spinnerReconstructTextPieces'].value
      button.sensitive = (1..pieces).none? do |index|
        grid.get_child_at(0, index - 1).text.strip().to_i() == 0 || # Index is non-numeric
        grid.get_child_at(1, index - 1).text.strip().empty?         # Shard is empty
      end
    end

    def ui_reconstruct_text
      piecesCount = @builder['spinnerReconstructTextPieces'].value
      grid = @builder['gridReconstructTextPieces']
      prime = @builder['entryReconstructTextPrimeModulator'].text.strip().to_i()

      pieces = (1..piecesCount).collect do |index|
        [
            grid.get_child_at(0, index - 1).text.strip().to_i(),
            Base64.urlsafe_decode64(grid.get_child_at(1, index - 1).text.strip())
        ]
      end

      secret = Hiss.interpolate_string(pieces, prime)
      @builder['labelReconstructTextSecret'].text = secret
      @builder['boxReconstructTextSecret'].show_all()
    end

    def ui_validate_file
      valid = true
      file = @builder['buttonChooseSecretFile'].file
      if (file)
        file.unref()
      else
        valid = false
      end

      valid = valid && @builder['spinnerTotalPiecesFile'].value >= @builder['spinnerRequiredPiecesFile'].value
      @builder['buttonGenerateFile'].sensitive = valid
    end

    def ui_generate_file
      secretFile = nil
      totalPieces = @builder['spinnerTotalPiecesFile'].value
      requiredPieces = @builder['spinnerRequiredPiecesFile'].value
      prime = 7919
      pieceFiles = nil

      begin
        secretFile = @builder['buttonChooseSecretFile'].file
        parent = secretFile.parent
        parentPath = parent.path
        chunks = secretFile.basename.split(/\./)
        basename = if chunks.length == 1
                     chunks[0]
                   else
                     chunks.slice!(-1)
                     chunks.join('.')
                   end
        pieceFiles = (1..totalPieces).collect do |index|
          path = Pathname.new(parentPath).join("#{basename}-#{index}.shard").to_s()
          file = Gio::File.new_for_path(path)
          [file, file.replace(nil, false, Gio::FileCreateFlags::NONE, nil)]
        end
        secretStream = secretFile.read()
        firstChunk = true
        while true
          # TODO: Progress
          buffer = secretStream.read(BUFFER_SIZE)
          break if (buffer.length == 0)

          Hiss.generate_string(buffer, totalPieces, requiredPieces, prime).each_with_index do |generatedBuffer, index|
            outputStream = pieceFiles[index][1]
            if firstChunk
              outputStream.write("#{generatedBuffer[0].to_s()}\n") # index
              outputStream.write("#{prime.to_s()}\n")              # prime
            end
            outputStream.write(generatedBuffer[1])                 # raw data
          end
        end

        # Done generating, show results
        @fileResultPath = parentPath
        @builder['frameResultsFile'].show_all()
      rescue => error
        # TODO: error output
        puts error
        raise
      ensure
        # Close/unref file handles
        parent.unref() if parent
        if secretStream
          secretStream.close()
          secretStream.unref()
        end
        secretFile.unref() if secretFile
        pieceFiles.each do |file|
          if file[1]
            file[1].close()
            file[1].unref()
          end
          file[0].unref() if file[0]
        end
      end
    end

    def ui_open_file
      file = @builder['buttonChooseSecretFile'].file
      parent = file.parent
      begin
        Gio.app_info_launch_default_for_uri(parent.uri)
      ensure
        file.unref()
        parent.unref()
      end
    end

    def ui_open_reconstruct_file
      Gio.app_info_launch_default_for_uri(@builder['chooserReconstructFileDestination'].uri)
    end

    def ui_validate_reconstruct_file
      destination = nil
      pieces = nil
      valid = false

      begin
        destination = @builder['chooserReconstructFileDestination'].file
        pieces = @builder['chooserReconstructFileChoosePieces'].files
        valid = true if destination && pieces && pieces.length > 2
        @builder['buttonReconstructFile'].sensitive = valid
        @builder['buttonReconstructFileDestination'].label = destination.basename if destination
        @builder['buttonReconstructFileChoosePieces'].label = "(#{pieces.length} files)" if pieces && pieces.length > 0
      ensure
        destination.unref() if destination
        if pieces
          pieces.each{ |piece| piece.unref() if piece }
        end
      end
    end

    def ui_choose_pieces_reconstruct_file
      dialog = @builder['chooserReconstructFileChoosePieces']
      dialog.run()
      dialog.hide()
      ui_validate_reconstruct_file()
    end

    def ui_choose_destination_reconstruct_file
      dialog = @builder['chooserReconstructFileDestination']
      dialog.run()
      dialog.hide()
      ui_validate_reconstruct_file()
    end

    def ui_reconstruct_file
      destination = nil
      pieces = nil

      begin
        destinationFile = @builder['chooserReconstructFileDestination'].file
        destination = [destinationFile, destinationFile.replace(nil, false, Gio::FileCreateFlags::NONE, nil)]
        pieces = @builder['chooserReconstructFileChoosePieces'].files.collect do |file|
          [file, file.read()]
        end

        # read header
        indices = []
        primes = []
        buffers = []
        pieces.each do |piece|
          header = piece[1].read(BUFFER_SIZE).split("\n", 3)
          indices << header[0].strip().to_i()
          primes << header[1].strip().to_i()
          buffers << header[2]
        end

        # TODO: header validation

        # Fill the remaining portion of the trailing buffer
        pieces.each_with_index do |piece, index|
          buffers[index] += piece[1].read(BUFFER_SIZE - buffers[index].length)
        end

        while buffers.none?{ |buffer| buffer.length == 0 }
          points = (1..buffers.length).collect{ |index| [indices[index - 1], buffers[index - 1]]}
          destination[1].write(Hiss.interpolate_string(points, primes[0]))
          buffers = pieces.collect{ |piece| piece[1].read(BUFFER_SIZE) }
        end
        @builder['frameReconstructFileResults'].show_all()
      ensure
        if destination[1]
          destination[1].close()
          destination[1].unref()
        end
        destination[0].unref() if destination[0]
        if pieces
          pieces.each do |piece|
            if piece[1]
              piece[1].close()
              piece[1].unref()
            end
            piece[0].unref() if piece
          end
        end
      end
    end

    def ui_quit
      Gtk.main_quit()
    end
  end
end