%Doctor.Config{
  ignore_modules: [
    ZenCex.EndpointRegistry
  ],
  ignore_paths: [],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 95,
  min_overall_spec_coverage: 95,
  min_overall_moduledoc_coverage: 100,
  raise: false,
  reporter: Doctor.Reporters.Short,
  struct_type_spec_required: true,
  umbrella: false,
  exception_moduledoc_required: true
}