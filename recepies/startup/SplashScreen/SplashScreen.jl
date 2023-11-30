module SplashScreen

using ModernGL, GLAbstraction, GLFW

const GLA = GLAbstraction

function create_splash_window()

    splash_width = 480
    splash_height = 320

    GLFW.WindowHint(GLFW.DECORATED, false)

    window = GLFW.Window(name="Splash Screen", resolution=(splash_width, splash_height))
    GLFW.MakeContextCurrent(window)

    monitor = GLFW.GetPrimaryMonitor()
    video_mode = GLFW.GetVideoMode(monitor)
    screen_width = video_mode.width
    screen_height = video_mode.height

    xpos = div(screen_width - splash_width, 2)
    ypos = div(screen_height - splash_height, 2)

    GLFW.SetWindowPos(window, xpos, ypos)

    GLA.set_context!(window)

    vsh = GLA.vert"""
    #version 150
    in vec2 position;

    void main(){
        gl_Position = vec4(position, 0, 1.0);
    }
    """

    fsh = GLA.frag"""
    #version 150
    out vec4 outColor;

    void main() {
        outColor = vec4(0.72, 0.67, 0.67, 1.0);
    }
    """
    prog = GLA.Program(vsh, fsh)

    triangle = GLA.VertexArray(GLA.generate_buffers(prog, GLA.GEOMETRY_DIVISOR, position=[(0.0, 0.5), (0.5, -0.5), (-0.5,-0.5)]))

    glClearColor(0.2, 0.3, 0.3, 1.0)  # Set clear color

    GLA.bind(prog)

    @async begin
        while !GLFW.WindowShouldClose(window)

            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
            GLA.bind(triangle)
            GLA.draw(triangle)
            GLFW.SwapBuffers(window)
            GLFW.PollEvents()

            # This looks fun!
            # if GLFW.GetKey(window, GLFW.KEY_ESCAPE) == GLFW.PRESS
            #     GLFW.SetWindowShouldClose(window, true)
            # end

            sleep(0.1) # No point to burn resources
            yield()
        end

        GLFW.DestroyWindow(window)
    end

    return window
end

close_window(window) = GLFW.SetWindowShouldClose(window, true)

end


# window = SplashScreen.create_splash_window()

# sleep(5)

# SplashScreen.close_window(window)
