module ElectronApp

using Electron

function (@main)(ARGS)
    # Create a new Electron window
    win = Window()
    
    # Load HTML content with Hello World message
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Hello World</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
                margin: 0;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            }
            h1 {
                color: white;
                font-size: 48px;
                text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
            }
        </style>
        <script>
            // Notify Julia when window is closing
            window.addEventListener('beforeunload', function() {
                sendMessageToJulia('window-closing');
            });
        </script>
    </head>
    <body>
        <h1>Hello World!</h1>
    </body>
    </html>
    """
    
    # Load the HTML content into the window
    load(win, html_content)

    # Wait until main window closed (a dirty approach)
    wait(win.app.proc)

    return win
end

export main

end # module ElectronApp
