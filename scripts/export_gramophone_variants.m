function exportInfo = export_gramophone_variants()
%EXPORT_GRAMOPHONE_VARIANTS Deprecated compatibility wrapper.
%   Rejected audition variants are no longer exported. The official
%   gramophone mode now uses the horn audition recipe through mode
%   "gramophone"; "gramophone_horn" remains only as an internal alias.

warning('exportGramophoneVariants:Deprecated', ...
    ['export_gramophone_variants is deprecated. ', ...
    'Exporting the official gramophone preset instead.']);
exportInfo = export_gramophone_candidates(false);
end
