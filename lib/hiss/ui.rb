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
    end

    def ui_quit
      Gtk.main_quit()
    end

    ### Generate Text ###

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

    ### Reconstruct Text ###

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

      begin
        secretFile = @builder['buttonChooseSecretFile'].file
        parent = secretFile.parent
        Hiss.generate_file(secretFile.path, totalPieces, requiredPieces, prime)

        # Done generating, show results
        @fileResultPath = parent.uri
        @builder['frameResultsFile'].show_all()
      ensure
        secretFile.unref() if secretFile
        parent.unref() if parent
      end
    end

    def ui_open_file
      Gio.app_info_launch_default_for_uri(@fileResultPath)
    end

    ### Reconstruct File ###

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
        pieces.each{ |piece| piece.unref() if piece } if pieces
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
        destination = @builder['chooserReconstructFileDestination'].file
        pieceFiles = @builder['chooserReconstructFileChoosePieces'].files
        pieces = pieceFiles.collect { |file| file.path }

        Hiss.interpolate_file(pieces, destination.path)
        @builder['frameReconstructFileResults'].show_all()
      ensure
        destination.unref() if destination
        pieceFiles.each { |piece| piece.unref() } if pieceFiles
      end
    end
  end
end