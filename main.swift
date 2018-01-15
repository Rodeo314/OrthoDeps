import Foundation

let application = OrthoToolCLI()
let termination = application.run()
exit(termination == true ? EXIT_SUCCESS : EXIT_FAILURE)
