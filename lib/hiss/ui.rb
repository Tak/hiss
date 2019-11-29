require 'gtk3'
require 'base64'

module Hiss
  class UI
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
      @builder['mainInfoBar'].hide()
    end

    def ui_quit
      Gtk.main_quit()
    end

    def self.flush_events
      while Gtk.events_pending?
        Gtk.main_iteration()
      end
    end

    def ui_display_error(message, error)
      @builder['labelError'].text = "#{message}: #{error}"
      @builder['mainInfoBar'].show()
    end

    def ui_clear_errors
      @builder['mainInfoBar'].hide()
    end

    ### Generate Text ###

    def ui_validate_text
      secret = @builder['entrySecretText'].text
      totalPieces = @builder['spinnerTotalPiecesText'].value
      requiredPieces = @builder['spinnerRequiredPiecesText'].value
      @builder['buttonGenerateText'].sensitive = !secret.empty? && totalPieces >= requiredPieces
      @builder['frameResultsText'].hide()
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
      progressBar = @builder['progressText']
      totalProgress = secret.length
      generateButton = @builder['buttonGenerateText']

      ui_clear_errors()
      generateButton.sensitive = false

      begin
        pieces, prime = Hiss.new(secret, totalPieces, requiredPieces).generate() do |progress|
          progressBar.fraction = progress.to_f() / totalProgress
          UI.flush_events()
        end
        @builder['labelPrimeText'].text = prime.to_s()
        grid = @builder['gridResultText']
        UI.clear_grid(grid)
        pieces.each_with_index do |piece, index|
          grid.insert_row(index)
          grid.attach(get_selectable_label(piece[0].to_s(), 1.0), 0, index, 1, 1)
          grid.attach(get_selectable_label(Base64.urlsafe_encode64(piece[1]), 0.25), 1, index, 1, 1)
        end
        progressBar.fraction = 1.0
        @builder['frameResultsText'].show_all()
      rescue => error
        ui_display_error('Error generating shards', error)
      end
      generateButton.sensitive = true
    end

    ### Reconstruct Text ###

    def get_index_entry
      entry = Gtk::Entry.new()
      entry.placeholder_text = 'Index'
      entry.input_purpose = Gtk::InputPurpose::DIGITS
      entry.signal_connect(:changed){ ui_validate_reconstruct_text() }
      return entry
    end

    def get_piece_entry
      entry = Gtk::Entry.new()
      entry.placeholder_text = 'Secret shard'
      entry.signal_connect(:changed){ ui_validate_reconstruct_text() }
      return entry
    end

    def ui_text_reconstruct_pieces_count_changed
      grid = @builder['gridReconstructTextPieces']
      UI.clear_grid(grid)
      pieces = @builder['spinnerReconstructTextPieces'].value
      (1..pieces).each do |index|
        grid.insert_row(index - 1)
        grid.attach(get_index_entry(), 0, index - 1, 1, 1)
        grid.attach(get_piece_entry(), 1, index - 1, 1, 1)
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
      begin
        valid = (1..pieces).none? do |index|
          grid.get_child_at(0, index - 1).text.strip().to_i() == 0 ||                  # Index is non-numeric
          Base64.urlsafe_decode64(grid.get_child_at(1, index - 1).text.strip()).empty? # Shard is invalid
        end
      rescue
        valid = false
      end

      button.sensitive = valid
    end

    def ui_reconstruct_text
      piecesCount = @builder['spinnerReconstructTextPieces'].value
      grid = @builder['gridReconstructTextPieces']
      prime = @builder['entryReconstructTextPrimeModulator'].text.strip().to_i()
      progressBar = @builder['progressReconstructText']

      pieces = (1..piecesCount).collect do |index|
        [
            grid.get_child_at(0, index - 1).text.strip().to_i(),
            Base64.urlsafe_decode64(grid.get_child_at(1, index - 1).text.strip())
        ]
      end
      totalProgress = pieces[0][1].length

      begin
        ui_clear_errors()
        secret = Hiss.interpolate_string(pieces, prime) do |progress|
          progressBar.fraction = progress.to_f() / totalProgress
          UI.flush_events()
        end
        progressBar.fraction = 1.0
        @builder['labelReconstructTextSecret'].text = secret
        @builder['boxReconstructTextSecret'].show_all()
      rescue => error
        ui_display_error('Error reconstructing text', error)
      end
    end

    ### Generate File ###

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
      parent = nil
      prime = 7919
      totalPieces = @builder['spinnerTotalPiecesFile'].value
      requiredPieces = @builder['spinnerRequiredPiecesFile'].value
      progressBar = @builder['progressFile']
      generateButton = @builder['buttonGenerateFile']

      begin
        ui_clear_errors()
        generateButton.sensitive = false
        secretFile = @builder['buttonChooseSecretFile'].file
        parent = secretFile.parent
        totalProgress = Pathname.new(secretFile.path).size

        Hiss.generate_file(secretFile.path, totalPieces, requiredPieces, prime) do |progress|
          progressBar.fraction = progress.to_f() / totalProgress
          UI.flush_events()
        end
        progressBar.fraction = 1.0

        # Done generating, show results
        @fileResultPath = parent.uri
        @builder['frameResultsFile'].show_all()
      rescue => error
        ui_display_error('Error generating shards', error)
      ensure
        secretFile.unref() if secretFile
        parent.unref() if parent
      end
      generateButton.sensitive = true
    end

    def ui_open_file
      begin
        Gio.app_info_launch_default_for_uri(@fileResultPath)
      rescue => error
        ui_display_error("Error opening #{@fileResultPath}", error)
      end
    end

    ### Reconstruct File ###

    def ui_open_reconstruct_file
      begin
      Gio.app_info_launch_default_for_uri("file://#{@fileReconstructedPath}")
      rescue => error
        ui_display_error("Error opening #{@fileReconstructedPath}", error)
      end
    end

    def ui_validate_reconstruct_file
      destination = nil
      pieces = nil
      valid = false

      begin
        pieces = @builder['chooserReconstructFileChoosePieces'].files
        valid = true if pieces && pieces.length > 1
        @builder['buttonReconstructFile'].sensitive = valid
        @builder['buttonReconstructFileChoosePieces'].label = "(#{pieces.length} files)" if pieces && pieces.length > 0
      ensure
        destination.unref() if destination
        pieces.each{ |piece| piece.unref() if piece } if pieces
      end
    end

    def ui_choose_pieces_reconstruct_file
      dialog = @builder['chooserReconstructFileChoosePieces']
      dialog.run()
      dialog.hide()
      ui_validate_reconstruct_file()
    end

    def ui_reconstruct_file
      destination = nil
      pieces = nil
      reconstructButton = @builder['buttonReconstructFile']

      begin
        ui_clear_errors()
        reconstructButton.sensitive = false
        pieceFiles = @builder['chooserReconstructFileChoosePieces'].files
        progressBar = @builder['progressReconstructFile']
        destination = pieceFiles[0].parent
        pieces = pieceFiles.collect { |file| file.path }
        totalProgress = Pathname.new(pieces[0]).size

        @fileReconstructedPath = Hiss.interpolate_file(pieces, destination.path) do |progress|
          progressBar.fraction = progress.to_f() / totalProgress
          UI.flush_events()
        end
        progressBar.fraction = 1.0

        @builder['frameReconstructFileResults'].show_all()
      rescue => error
        ui_display_error('Error reconstructing file', error)
      ensure
        destination.unref() if destination
        pieceFiles.each { |piece| piece.unref() } if pieceFiles
      end
      reconstructButton.sensitive = true
    end
  end
end