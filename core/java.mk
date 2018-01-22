# Target Java.
# Requires:
# LOCAL_MODULE_SUFFIX
# LOCAL_MODULE_CLASS
# all_res_assets

ifeq ($(TARGET_BUILD_PDK),true)
ifeq ($(TARGET_BUILD_PDK_JAVA_PLATFORM),)
# LOCAL_SDK not defined or set to current
ifeq ($(filter-out current,$(LOCAL_SDK_VERSION)),)
ifneq ($(LOCAL_NO_STANDARD_LIBRARIES),true)
LOCAL_SDK_VERSION := $(PDK_BUILD_SDK_VERSION)
endif #!LOCAL_NO_STANDARD_LIBRARIES
endif
endif # !PDK_JAVA
endif #PDK

LOCAL_NO_STANDARD_LIBRARIES:=$(strip $(LOCAL_NO_STANDARD_LIBRARIES))
LOCAL_SDK_VERSION:=$(strip $(LOCAL_SDK_VERSION))

ifneq ($(LOCAL_SDK_VERSION),)
  ifeq ($(LOCAL_NO_STANDARD_LIBRARIES),true)
    $(error $(LOCAL_PATH): Must not define both LOCAL_NO_STANDARD_LIBRARIES and LOCAL_SDK_VERSION)
  else
    ifeq ($(strip $(filter $(LOCAL_SDK_VERSION),$(TARGET_AVAILABLE_SDK_VERSIONS))),)
      $(error $(LOCAL_PATH): Invalid LOCAL_SDK_VERSION '$(LOCAL_SDK_VERSION)' \
             Choices are: $(TARGET_AVAILABLE_SDK_VERSIONS))
    else
      ifeq ($(LOCAL_SDK_VERSION)$(TARGET_BUILD_APPS),current)
        # Use android_stubs_current if LOCAL_SDK_VERSION is current and no TARGET_BUILD_APPS.
        LOCAL_JAVA_LIBRARIES := android_stubs_current $(LOCAL_JAVA_LIBRARIES)
      else ifeq ($(LOCAL_SDK_VERSION)$(TARGET_BUILD_APPS),system_current)
        LOCAL_JAVA_LIBRARIES := android_system_stubs_current $(LOCAL_JAVA_LIBRARIES)
      else ifeq ($(LOCAL_SDK_VERSION)$(TARGET_BUILD_APPS),test_current)
        LOCAL_JAVA_LIBRARIES := android_test_stubs_current $(LOCAL_JAVA_LIBRARIES)
      else
        LOCAL_JAVA_LIBRARIES := sdk_v$(LOCAL_SDK_VERSION) $(LOCAL_JAVA_LIBRARIES)
      endif

    endif
  endif
else
  ifneq ($(LOCAL_NO_STANDARD_LIBRARIES),true)
    LOCAL_JAVA_LIBRARIES := $(TARGET_DEFAULT_JAVA_LIBRARIES) $(LOCAL_JAVA_LIBRARIES)
  endif
endif

proto_sources := $(filter %.proto,$(LOCAL_SRC_FILES))
ifneq ($(proto_sources),)
ifeq ($(LOCAL_PROTOC_OPTIMIZE_TYPE),micro)
    LOCAL_STATIC_JAVA_LIBRARIES += libprotobuf-java-micro
else
  ifeq ($(LOCAL_PROTOC_OPTIMIZE_TYPE),nano)
    LOCAL_STATIC_JAVA_LIBRARIES += libprotobuf-java-nano
  else
    LOCAL_STATIC_JAVA_LIBRARIES += libprotobuf-java-lite
  endif
endif
endif

# LOCAL_STATIC_JAVA_AAR_LIBRARIES and LOCAL_STATIC_ANDROID_LIBRARIES are also LOCAL_STATIC_JAVA_LIBRARIES.
LOCAL_STATIC_JAVA_LIBRARIES := $(strip $(LOCAL_STATIC_JAVA_LIBRARIES) \
    $(LOCAL_STATIC_JAVA_AAR_LIBRARIES) \
    $(LOCAL_STATIC_ANDROID_LIBRARIES))
# LOCAL_SHARED_ANDROID_LIBRARIES are also LOCAL_JAVA_LIBRARIES.
LOCAL_JAVA_LIBRARIES := $(sort $(LOCAL_JAVA_LIBRARIES) $(LOCAL_SHARED_ANDROID_LIBRARIES))

LOCAL_BUILT_MODULE_STEM := $(strip $(LOCAL_BUILT_MODULE_STEM))
ifeq ($(LOCAL_BUILT_MODULE_STEM),)
$(error $(LOCAL_PATH): Target java template must define LOCAL_BUILT_MODULE_STEM)
endif
ifneq ($(filter classes-compiled.jar classes.jar,$(LOCAL_BUILT_MODULE_STEM)),)
$(error LOCAL_BUILT_MODULE_STEM may not be "$(LOCAL_BUILT_MODULE_STEM)")
endif


##############################################################################
# Define the intermediate targets before including base_rules so they get
# the correct environment.
##############################################################################

intermediates := $(call local-intermediates-dir)
intermediates.COMMON := $(call local-intermediates-dir,COMMON)

# Choose leaf name for the compiled jar file.
ifeq ($(LOCAL_EMMA_INSTRUMENT),true)
full_classes_compiled_jar_leaf := classes-no-debug-var.jar
built_dex_intermediate_leaf := no-local
else
full_classes_compiled_jar_leaf := classes-full-debug.jar
built_dex_intermediate_leaf := with-local
endif

LOCAL_PROGUARD_ENABLED :=

full_classes_compiled_jar := $(intermediates.COMMON)/$(full_classes_compiled_jar_leaf)
jarjar_leaf := classes-jarjar.jar
full_classes_desugar_jar := $(intermediates.COMMON)/classes-desugar.jar
full_classes_jarjar_jar := $(intermediates.COMMON)/$(jarjar_leaf)
emma_intermediates_dir := $(intermediates.COMMON)/emma_out
# emma is hardcoded to use the leaf name of its input for the output file --
# only the output directory can be changed
full_classes_emma_jar := $(emma_intermediates_dir)/lib/$(jarjar_leaf)
built_dex_intermediate := $(intermediates.COMMON)/$(built_dex_intermediate_leaf)/classes.dex
full_classes_stubs_jar := $(intermediates.COMMON)/stubs.jar

ifeq ($(LOCAL_MODULE_CLASS)$(LOCAL_SRC_FILES)$(LOCAL_STATIC_JAVA_LIBRARIES)$(LOCAL_SOURCE_FILES_ALL_GENERATED),APPS)
# If this is an apk without any Java code (e.g. framework-res), we should skip compiling Java.
full_classes_jar :=
built_dex :=
else
full_classes_jar := $(intermediates.COMMON)/classes.jar
built_dex := $(intermediates.COMMON)/classes.dex
endif

LOCAL_INTERMEDIATE_TARGETS += \
    $(full_classes_compiled_jar) \
    $(full_classes_jarjar_jar) \
    $(full_classes_desugar_jar) \
    $(full_classes_emma_jar) \
    $(full_classes_jar) \
    $(built_dex_intermediate) \
    $(built_dex) \
    $(full_classes_stubs_jar)


LOCAL_INTERMEDIATE_SOURCE_DIR := $(intermediates.COMMON)/src

###############################################################
## .rs files: RenderScript sources to .java files and .bc files
## .fs files: Filterscript sources to .java files and .bc files
###############################################################
renderscript_sources := $(filter %.rs %.fs,$(LOCAL_SRC_FILES))
# Because names of the java files from RenderScript are unknown until the
# .rs file(s) are compiled, we have to depend on a timestamp file.
RenderScript_file_stamp :=
rs_generated_res_dir :=
rs_compatibility_jni_libs :=
ifneq ($(renderscript_sources),)
renderscript_sources_fullpath := $(addprefix $(LOCAL_PATH)/, $(renderscript_sources))
RenderScript_file_stamp := $(LOCAL_INTERMEDIATE_SOURCE_DIR)/RenderScript.stamp
renderscript_intermediate.COMMON := $(LOCAL_INTERMEDIATE_SOURCE_DIR)/renderscript

# Defaulting to an empty string uses the latest available platform SDK.
renderscript_target_api :=

ifneq (,$(LOCAL_RENDERSCRIPT_TARGET_API))
  renderscript_target_api := $(LOCAL_RENDERSCRIPT_TARGET_API)
else
  ifneq (,$(LOCAL_SDK_VERSION))
    # Set target-api for LOCAL_SDK_VERSIONs other than current.
    ifneq (,$(filter-out current system_current test_current, $(LOCAL_SDK_VERSION)))
      renderscript_target_api := $(LOCAL_SDK_VERSION)
    endif
  endif  # LOCAL_SDK_VERSION is set
endif  # LOCAL_RENDERSCRIPT_TARGET_API is set

# For 64-bit, we always have to upgrade to at least 21 for compat build.
ifneq ($(LOCAL_RENDERSCRIPT_COMPATIBILITY),)
  ifeq ($(TARGET_IS_64_BIT),true)
    ifneq ($(filter $(RSCOMPAT_32BIT_ONLY_API_LEVELS),$(renderscript_target_api)),)
      renderscript_target_api := 21
    endif
  endif
endif

ifeq ($(LOCAL_RENDERSCRIPT_CC),)
LOCAL_RENDERSCRIPT_CC := $(LLVM_RS_CC)
endif

# Turn on all warnings and warnings as errors for RS compiles.
# This can be disabled with LOCAL_RENDERSCRIPT_FLAGS := -Wno-error
renderscript_flags := -Wall -Werror
renderscript_flags += $(LOCAL_RENDERSCRIPT_FLAGS)

# prepend the RenderScript system include path
ifneq ($(filter-out current system_current test_current,$(LOCAL_SDK_VERSION))$(if $(TARGET_BUILD_APPS),$(filter current system_current test_current,$(LOCAL_SDK_VERSION))),)
# if a numeric LOCAL_SDK_VERSION, or current LOCAL_SDK_VERSION with TARGET_BUILD_APPS
LOCAL_RENDERSCRIPT_INCLUDES := \
    $(HISTORICAL_SDK_VERSIONS_ROOT)/renderscript/clang-include \
    $(HISTORICAL_SDK_VERSIONS_ROOT)/renderscript/include \
    $(LOCAL_RENDERSCRIPT_INCLUDES)
else
LOCAL_RENDERSCRIPT_INCLUDES := \
    $(TOPDIR)external/clang/lib/Headers \
    $(TOPDIR)frameworks/rs/scriptc \
    $(LOCAL_RENDERSCRIPT_INCLUDES)
endif

ifneq ($(LOCAL_RENDERSCRIPT_INCLUDES_OVERRIDE),)
LOCAL_RENDERSCRIPT_INCLUDES := $(LOCAL_RENDERSCRIPT_INCLUDES_OVERRIDE)
endif

bc_files := $(patsubst %.fs,%.bc, $(patsubst %.rs,%.bc, $(notdir $(renderscript_sources))))
bc_dep_files := $(addprefix $(renderscript_intermediate.COMMON)/,$(patsubst %.bc,%.d,$(bc_files)))

$(RenderScript_file_stamp): PRIVATE_RS_INCLUDES := $(LOCAL_RENDERSCRIPT_INCLUDES)
$(RenderScript_file_stamp): PRIVATE_RS_CC := $(LOCAL_RENDERSCRIPT_CC)
$(RenderScript_file_stamp): PRIVATE_RS_FLAGS := $(renderscript_flags)
$(RenderScript_file_stamp): PRIVATE_RS_SOURCE_FILES := $(renderscript_sources_fullpath)
# By putting the generated java files into $(LOCAL_INTERMEDIATE_SOURCE_DIR), they will be
# automatically found by the java compiling function transform-java-to-classes.jar.
$(RenderScript_file_stamp): PRIVATE_RS_OUTPUT_DIR := $(renderscript_intermediate.COMMON)
$(RenderScript_file_stamp): PRIVATE_RS_TARGET_API := $(renderscript_target_api)
$(RenderScript_file_stamp): PRIVATE_DEP_FILES := $(bc_dep_files)
$(RenderScript_file_stamp): $(renderscript_sources_fullpath) $(LOCAL_RENDERSCRIPT_CC)
	$(transform-renderscripts-to-java-and-bc)

# include the dependency files (.d/.P) generated by llvm-rs-cc.
$(call include-depfile,$(RenderScript_file_stamp).P,$(RenderScript_file_stamp))

ifneq ($(LOCAL_RENDERSCRIPT_COMPATIBILITY),)


ifeq ($(filter $(RSCOMPAT_32BIT_ONLY_API_LEVELS),$(renderscript_target_api)),)
ifeq ($(TARGET_IS_64_BIT),true)
renderscript_intermediate.bc_folder := $(renderscript_intermediate.COMMON)/res/raw/bc64/
else
renderscript_intermediate.bc_folder := $(renderscript_intermediate.COMMON)/res/raw/bc32/
endif
else
renderscript_intermediate.bc_folder := $(renderscript_intermediate.COMMON)/res/raw/
endif

rs_generated_bc := $(addprefix \
    $(renderscript_intermediate.bc_folder), $(bc_files))

renderscript_intermediate := $(intermediates)/renderscript

# We don't need the .so files in bundled branches
# Prevent these from showing up on the device
# One exception is librsjni.so, which is needed for
# both native path and compat path.
rs_jni_lib := $(TARGET_OUT_INTERMEDIATE_LIBRARIES)/librsjni.so
LOCAL_JNI_SHARED_LIBRARIES += librsjni

ifneq (,$(TARGET_BUILD_APPS)$(FORCE_BUILD_RS_COMPAT))

rs_compatibility_jni_libs := $(addprefix \
    $(renderscript_intermediate)/librs., \
    $(patsubst %.bc,%.so, $(bc_files)))

$(rs_generated_bc) : $(RenderScript_file_stamp)

rs_support_lib := $(TARGET_OUT_INTERMEDIATE_LIBRARIES)/libRSSupport.so
LOCAL_JNI_SHARED_LIBRARIES += libRSSupport

rs_support_io_lib :=
# check if the target api level support USAGE_IO
ifeq ($(filter $(RSCOMPAT_NO_USAGEIO_API_LEVELS),$(renderscript_target_api)),)
rs_support_io_lib := $(TARGET_OUT_INTERMEDIATE_LIBRARIES)/libRSSupportIO.so
LOCAL_JNI_SHARED_LIBRARIES += libRSSupportIO
endif


$(rs_compatibility_jni_libs): $(RenderScript_file_stamp) $(RS_PREBUILT_CLCORE) \
    $(rs_support_lib) $(rs_support_io_lib) $(rs_jni_lib) $(rs_compiler_rt)
$(rs_compatibility_jni_libs): $(BCC_COMPAT)
$(rs_compatibility_jni_libs): PRIVATE_CXX := $(CXX_WRAPPER) $(TARGET_CXX)
$(rs_compatibility_jni_libs): $(renderscript_intermediate)/librs.%.so: \
    $(renderscript_intermediate.bc_folder)%.bc
	$(transform-bc-to-so)

endif

endif

LOCAL_INTERMEDIATE_TARGETS += $(RenderScript_file_stamp)
# Make sure the generated resource will be added to the apk.
rs_generated_res_dir := $(renderscript_intermediate.COMMON)/res
LOCAL_RESOURCE_DIR := $(rs_generated_res_dir) $(LOCAL_RESOURCE_DIR)
endif


###########################################################
## AIDL: Compile .aidl files to .java
###########################################################
aidl_sources := $(filter %.aidl,$(LOCAL_SRC_FILES))

ifneq ($(strip $(aidl_sources)),)
aidl_java_sources := $(patsubst %.aidl,%.java,$(addprefix $(intermediates.COMMON)/src/, $(aidl_sources)))
aidl_sources := $(addprefix $(LOCAL_PATH)/, $(aidl_sources))

aidl_preprocess_import :=
ifdef LOCAL_SDK_VERSION
ifneq ($(filter current system_current test_current, $(LOCAL_SDK_VERSION)$(TARGET_BUILD_APPS)),)
  # LOCAL_SDK_VERSION is current and no TARGET_BUILD_APPS
  aidl_preprocess_import := $(TARGET_OUT_COMMON_INTERMEDIATES)/framework.aidl
else
  aidl_preprocess_import := $(HISTORICAL_SDK_VERSIONS_ROOT)/$(LOCAL_SDK_VERSION)/framework.aidl
endif # not current or system_current
else
# build against the platform.
LOCAL_AIDL_INCLUDES += $(FRAMEWORKS_BASE_JAVA_SRC_DIRS)
endif # LOCAL_SDK_VERSION
$(aidl_java_sources): PRIVATE_AIDL_FLAGS := -b $(addprefix -p,$(aidl_preprocess_import)) -I$(LOCAL_PATH) -I$(LOCAL_PATH)/src $(addprefix -I,$(LOCAL_AIDL_INCLUDES)) $(LOCAL_AIDL_FLAGS)

$(aidl_java_sources): $(intermediates.COMMON)/src/%.java: \
        $(LOCAL_PATH)/%.aidl \
        $(LOCAL_MODULE_MAKEFILE_DEP) \
        $(LOCAL_ADDITIONAL_DEPENDENCIES) \
        $(AIDL) \
        $(aidl_preprocess_import)
	$(transform-aidl-to-java)
$(foreach java,$(aidl_java_sources), \
    $(call include-depfile,$(java:%.java=%.P),$(java)))

else
aidl_java_sources :=
endif

##########################################

# All of the rules after full_classes_compiled_jar are very unlikely
# to fail except for bugs in their respective tools.  If you would
# like to run these rules, add the "all" modifier goal to the make
# command line.
ifndef LOCAL_CHECKED_MODULE
ifdef full_classes_jar
LOCAL_CHECKED_MODULE := $(full_classes_compiled_jar)
endif
endif

#######################################
include $(BUILD_SYSTEM)/base_rules.mk
#######################################

###########################################################
## logtags: emit java source
###########################################################
ifneq ($(strip $(logtags_sources)),)

logtags_java_sources := $(patsubst %.logtags,%.java,$(addprefix $(intermediates.COMMON)/src/, $(logtags_sources)))
logtags_sources := $(addprefix $(LOCAL_PATH)/, $(logtags_sources))

$(logtags_java_sources): $(intermediates.COMMON)/src/%.java: $(LOCAL_PATH)/%.logtags $(TARGET_OUT_COMMON_INTERMEDIATES)/all-event-log-tags.txt
	$(transform-logtags-to-java)

else
logtags_java_sources :=
endif

##########################################
java_sources := $(addprefix $(LOCAL_PATH)/, $(filter %.java,$(LOCAL_SRC_FILES))) $(aidl_java_sources) $(logtags_java_sources) \
                $(filter %.java,$(LOCAL_GENERATED_SOURCES))
all_java_sources := $(java_sources) $(addprefix $(TARGET_OUT_COMMON_INTERMEDIATES)/, $(filter %.java,$(LOCAL_INTERMEDIATE_SOURCES)))

include $(BUILD_SYSTEM)/java_common.mk

#######################################
# defines built_odex along with rule to install odex
include $(BUILD_SYSTEM)/dex_preopt_odex_install.mk
#######################################

# Make sure there's something to build.
ifdef full_classes_jar
ifndef need_compile_java
$(error $(LOCAL_PATH): Target java module does not define any source or resource files)
endif
endif

# Since we're using intermediates.COMMON, make sure that it gets cleaned
# properly.
$(cleantarget): PRIVATE_CLEAN_FILES += $(intermediates.COMMON)

ifdef full_classes_jar

# Droiddoc isn't currently able to generate stubs for modules, so we're just
# allowing it to use the classes.jar as the "stubs" that would be use to link
# against, for the cases where someone needs the jar to link against.
# - Use the classes.jar instead of the handful of other intermediates that
#   we have, because it's the most processed, but still hasn't had dex run on
#   it, so it's closest to what's on the device.
# - This extra copy, with the dependency on LOCAL_BUILT_MODULE allows the
#   PRIVATE_ vars to be preserved.
$(full_classes_stubs_jar): PRIVATE_SOURCE_FILE := $(full_classes_jar)
$(full_classes_stubs_jar) : $(LOCAL_BUILT_MODULE) | $(ACP)
	@echo Copying $(PRIVATE_SOURCE_FILE)
	$(hide) $(ACP) -fp $(PRIVATE_SOURCE_FILE) $@
ALL_MODULES.$(LOCAL_MODULE).STUBS := $(full_classes_stubs_jar)

# The layers file allows you to enforce a layering between java packages.
# Run build/tools/java-layers.py for more details.
layers_file := $(addprefix $(LOCAL_PATH)/, $(LOCAL_JAVA_LAYERS_FILE))
$(full_classes_compiled_jar): PRIVATE_JAVA_LAYERS_FILE := $(layers_file)
$(full_classes_compiled_jar): PRIVATE_WARNINGS_ENABLE := $(LOCAL_WARNINGS_ENABLE)

ifdef LOCAL_RMTYPEDEFS
$(full_classes_compiled_jar): | $(RMTYPEDEFS)
endif

# Compile the java files to a .jar file.
# This intentionally depends on java_sources, not all_java_sources.
# Deps for generated source files must be handled separately,
# via deps on the target that generates the sources.
$(full_classes_compiled_jar): PRIVATE_JAVACFLAGS := $(GLOBAL_JAVAC_DEBUG_FLAGS) $(LOCAL_JAVACFLAGS)
$(full_classes_compiled_jar): PRIVATE_JAR_EXCLUDE_FILES := $(LOCAL_JAR_EXCLUDE_FILES)
$(full_classes_compiled_jar): PRIVATE_JAR_PACKAGES := $(LOCAL_JAR_PACKAGES)
$(full_classes_compiled_jar): PRIVATE_JAR_EXCLUDE_PACKAGES := $(LOCAL_JAR_EXCLUDE_PACKAGES)
$(full_classes_compiled_jar): PRIVATE_DONT_DELETE_JAR_META_INF := $(LOCAL_DONT_DELETE_JAR_META_INF)
$(full_classes_compiled_jar): \
        $(java_sources) \
        $(java_resource_sources) \
        $(full_java_lib_deps) \
        $(jar_manifest_file) \
        $(layers_file) \
        $(RenderScript_file_stamp) \
        $(proto_java_sources_file_stamp) \
        $(LOCAL_MODULE_MAKEFILE_DEP) \
        $(LOCAL_ADDITIONAL_DEPENDENCIES)
	$(transform-java-to-classes.jar)

# Run jarjar if necessary, otherwise just copy the file.
ifneq ($(strip $(LOCAL_JARJAR_RULES)),)
$(full_classes_jarjar_jar): PRIVATE_JARJAR_RULES := $(LOCAL_JARJAR_RULES)
$(full_classes_jarjar_jar): $(full_classes_compiled_jar) $(LOCAL_JARJAR_RULES) | $(JARJAR)
	@echo JarJar: $@
	$(hide) java -jar $(JARJAR) process $(PRIVATE_JARJAR_RULES) $< $@
else
$(full_classes_jarjar_jar): $(full_classes_compiled_jar) | $(ACP)
	@echo Copying: $@
	$(hide) $(ACP) -fp $< $@
endif

full_classes_jar_source := $(full_classes_jarjar_jar)

ifeq ($(LOCAL_EMMA_INSTRUMENT),true)
$(full_classes_emma_jar): PRIVATE_EMMA_COVERAGE_FILE := $(intermediates.COMMON)/coverage.emma.ignore
$(full_classes_emma_jar): PRIVATE_EMMA_INTERMEDIATES_DIR := $(emma_intermediates_dir)
# module level coverage filter can be defined using LOCAL_EMMA_COVERAGE_FILTER
# in Android.mk
ifdef LOCAL_EMMA_COVERAGE_FILTER
$(full_classes_emma_jar): PRIVATE_EMMA_COVERAGE_FILTER := $(LOCAL_EMMA_COVERAGE_FILTER)
else
# by default, avoid applying emma instrumentation onto emma classes itself,
# otherwise there will be exceptions thrown
$(full_classes_emma_jar): PRIVATE_EMMA_COVERAGE_FILTER := *,-emma,-emmarun,-com.vladium.*
endif
# this rule will generate both $(PRIVATE_EMMA_COVERAGE_FILE) and
# $(full_classes_emma_jar)
$(full_classes_emma_jar): $(full_classes_jarjar_jar) | $(EMMA_JAR)
	$(transform-classes.jar-to-emma)
full_classes_jar_source := $(full_classes_emma_jar)
endif


# Keep a copy of the jar just before proguard processing.
$(full_classes_jar): $(full_classes_jar_source) | $(ACP)
	@echo Copying: $@
	$(hide) $(ACP) -fp $< $@

$(call define-jar-to-toc-rule, $(full_classes_jar))

# Override PRIVATE_INTERMEDIATES_DIR so that install-dex-debug
# will work even when intermediates != intermediates.COMMON.
$(built_dex_intermediate): PRIVATE_INTERMEDIATES_DIR := $(intermediates.COMMON)
$(built_dex_intermediate): PRIVATE_DX_FLAGS := $(LOCAL_DX_FLAGS)
# If you instrument class files that have local variable debug information in
# them emma does not correctly maintain the local variable table.
# This will cause an error when you try to convert the class files for Android.
# The workaround here is to build different dex file here based on emma switch
# then later copy into classes.dex. When emma is on, dx is run with --no-locals
# option to remove local variable information
ifeq ($(LOCAL_EMMA_INSTRUMENT),true)
$(built_dex_intermediate): PRIVATE_DX_FLAGS += --no-locals
endif

$(built_dex_intermediate): $(full_classes_jar) $(DX)
	$(transform-classes.jar-to-dex)

$(built_dex): $(built_dex_intermediate) | $(ACP)
	@echo Copying: $@
	$(hide) mkdir -p $(dir $@)
	$(hide) rm -f $(dir $@)/classes*.dex
	$(hide) $(ACP) -fp $(dir $<)/classes*.dex $(dir $@)
ifneq ($(GENERATE_DEX_DEBUG),)
	$(install-dex-debug)
endif

findbugs_xml := $(intermediates.COMMON)/findbugs.xml

$(findbugs_xml) : PRIVATE_JAR_FILE := $(full_classes_jar)
$(findbugs_xml) : PRIVATE_AUXCLASSPATH := $(addprefix -auxclasspath ,$(strip \
								$(call normalize-path-list,$(filter %.jar,\
										$(full_java_libs)))))
# We can't depend directly on full_classes_jar because the PRIVATE_
# vars won't be set up correctly.
$(findbugs_xml) : $(LOCAL_BUILT_MODULE)
	@echo Findbugs: $@
	$(hide) $(FINDBUGS) -textui -effort:min -xml:withMessages \
		$(PRIVATE_AUXCLASSPATH) \
		$(PRIVATE_JAR_FILE) \
		> $@

ALL_FINDBUGS_FILES += $(findbugs_xml)

findbugs_html := $(PRODUCT_OUT)/findbugs/$(LOCAL_MODULE).html
$(findbugs_html) : PRIVATE_XML_FILE := $(findbugs_xml)
$(LOCAL_MODULE)-findbugs : $(findbugs_html)
$(findbugs_html) : $(findbugs_xml)
	@mkdir -p $(dir $@)
	@echo ConvertXmlToText: $@
	$(hide) $(FINDBUGS_DIR)/convertXmlToText -html:fancy.xsl $(PRIVATE_XML_FILE) \
	> $@

$(LOCAL_MODULE)-findbugs : $(findbugs_html)

endif  # full_classes_jar is defined

ifneq (,$(filter-out current system_current test_current, $(LOCAL_SDK_VERSION)))
$(LOCAL_INTERMEDIATE_TARGETS): PRIVATE_DEFAULT_APP_TARGET_SDK := $(LOCAL_SDK_VERSION)
$(LOCAL_INTERMEDIATE_TARGETS): PRIVATE_SDK_VERSION := $(LOCAL_SDK_VERSION)
else
$(LOCAL_INTERMEDIATE_TARGETS): PRIVATE_DEFAULT_APP_TARGET_SDK := $(DEFAULT_APP_TARGET_SDK)
$(LOCAL_INTERMEDIATE_TARGETS): PRIVATE_SDK_VERSION := $(PLATFORM_SDK_VERSION)
endif