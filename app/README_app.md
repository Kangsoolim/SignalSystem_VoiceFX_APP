# App Module Notes

This folder is reserved for future MATLAB App Designer integration.

Do not create or modify `.mlapp` files in the current framework stage. Future
App callbacks should stay thin: read UI parameters, build/update `config`, call
functions in `core/` and `modules/`, then display or play results.

Core audio algorithms should not be written directly inside App callbacks.
