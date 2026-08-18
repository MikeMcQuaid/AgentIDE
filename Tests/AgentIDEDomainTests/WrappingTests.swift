import AgentIDEDomain
import Testing

/// Exercises putting hand-wrapped commit prose back onto one line
/// per point, which is what a pull request body wants.
struct WrappingTests {
    @Test
    func `joins wrapped bullets and paragraphs into whole lines`() {
        let message = """
        - Run lint without concurrency on standard runners before
          a candidate enters the expensive stage.
        - Let one candidate finish while the newest waiting candidate
          replaces older pending work through the default queue.

        A paragraph that was wrapped by hand at a narrow column
        also becomes one line again.
        """
        #expect(Wrapping.unwrapped(message) == """
        - Run lint without concurrency on standard runners before a candidate enters the expensive stage.
        - Let one candidate finish while the newest waiting candidate replaces older pending work through \
        the default queue.

        A paragraph that was wrapped by hand at a narrow column also becomes one line again.
        """)
    }

    @Test
    func `leaves blocks that mean something by their lines alone`() {
        let message = """
        # Heading
        Its paragraph.

        ```sh
        script/style --fix
        script/test
        ```

            indented code stays put

        > A quote
        > with two lines.
        """
        #expect(Wrapping.unwrapped(message) == message)
    }

    @Test
    func `an unwrapped body is left exactly as it is`() {
        let message = "One line.\n\n- One bullet.\n- Another bullet."
        #expect(Wrapping.unwrapped(message) == message)
    }
}
