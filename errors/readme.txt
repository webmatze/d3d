* INFO: Getting production errors.
The last exception that occurred will be written to this directory (in
production releases and in dev for testing purposes). If a hard crash
occurs for your game, you can have that information sent to you by the
user by doing the following:

#+begin_src ruby
  def boot args
    # on game boot, see if "errors/last.txt" exists
    last_exception = GTK.read_file "errors/last.txt"

    # if it does, kick off the users default mail app
    if last_exception
      # delete the file (or perform whatever archiving you'd like) so
      # the email flow doesn't occur on next app open
      GTK.delete_file_if_exist "errors/last.txt"

      # construct an email and have it open in user's default email application
      GTK.mailto email: "email@example.com", subject: "#{Cvars["game_metadata.gametitle"].value} v#{Cvars["game_metadata.version"].value}", body: last_exception
    end
  end
#+end_src

If you want to disable (or override) this behavior. Add the following to the top of main.rb:
#+begin_src ruby
  class GTK::Runtime
    def export_error! exception_text
      # leave the function body blank to disable completely
      # or override the default behavior to your liking
      # GTK.write_file "custom-location/custom-file-name.txt", exception_text
    end
  end
#+end_src
