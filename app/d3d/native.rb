module D3D
  # Optional native acceleration through the D3D Pro C extension (needs
  # DragonRuby Indie or Pro; source app/d3d/ext/d3d_ext.c, built with bin/build-ext,
  # both only in D3D Pro). The engine never needs
  # it: every native function has a pure Ruby fallback, and nothing native is
  # used until a game calls D3D::Native.load and it succeeds. Without a Pro
  # license, without a built library or on CRuby, load returns false and the
  # engine stays pure Ruby.
  module Native
    extend self

    LIBRARY = 'd3d_ext'
    # Bump together with the API constant of the C source whenever a native function
    # changes its arguments or results; a library built for another API is
    # refused and the engine stays pure Ruby.
    API = 1

    # Loads native/<platform>/d3d_ext.* from the game dir. Returns true when
    # D3D::Ext is ready (enabled from then on), false otherwise.
    def load(library = LIBRARY)
      unless D3D.constants.include?(:Ext)
        # DR.respond_to?(:ffi_misc) is false even where it works, so just call
        # it; any error from the loader ends up in the rescue below.
        return false unless Object.const_defined?(:DR)

        DR.ffi_misc.gtk_dlopen(library)
        return false unless D3D.constants.include?(:Ext)
      end
      return enable if loaded?

      warn_api_mismatch
      false
    rescue StandardError
      false
    end

    # True when the extension is loaded and not switched off.
    def enabled?
      @enabled == true
    end

    # Switches native code off (e.g. to compare against the Ruby fallback)
    # or back on; turning it on only works once the extension is loaded.
    def enabled=(value)
      @enabled = value && loaded? ? true : false
    end

    # True when D3D::Ext exists and was built for this engine's API.
    def loaded?
      D3D.constants.include?(:Ext) && ext_api == API
    end

    private

    def enable
      @enabled = true
    end

    def ext_api
      D3D::Ext.constants.include?(:API) ? D3D::Ext::API : 0
    end

    def warn_api_mismatch
      puts "D3D: d3d_ext was built for API #{ext_api}, the engine expects #{API}; " \
           'rebuild it or update D3D Pro. Running pure Ruby.'
    end
  end
end
