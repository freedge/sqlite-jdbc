
include Makefile.common

RESOURCE_DIR = src/main/resources

.phony: all package win32 win64 mac32 linux32 linux64 linux-arm linux-armhf native native-all deploy

all: jni-header package

deploy: 
	mvn package deploy -DperformRelease=true

MVN:=mvn
SRC:=src/main/java
SQLITE_OUT:=$(TARGET)/$(sqlite)-$(OS_NAME)-$(OS_ARCH)
SQLITE_ARCHIVE:=$(TARGET)/$(sqlite)-amal.zip
SQLITE_UNPACKED:=$(TARGET)/sqlite-unpack.log
SQLITE_AMAL_DIR=$(TARGET)/$(SQLITE_AMAL_PREFIX)

CCFLAGS:= -I$(SQLITE_OUT) -I$(SQLITE_AMAL_DIR) $(CCFLAGS)

$(SQLITE_UNPACKED): 
	mkdir -p $(TARGET)/$(SQLITE_AMAL_PREFIX)
	cp -r $(HOME)/GIT//sqlite/* $(TARGET)/$(SQLITE_AMAL_PREFIX)


$(TARGET)/common-lib/org/sqlite/%.class: src/main/java/org/sqlite/%.java
	@mkdir -p $(@D)
	$(JAVAC) -source 1.5 -target 1.5 -sourcepath $(SRC) -d $(TARGET)/common-lib $<

jni-header: $(TARGET)/common-lib/NativeDB.h

$(TARGET)/common-lib/NativeDB.h: $(TARGET)/common-lib/org/sqlite/core/NativeDB.class
	$(JAVAH) -classpath $(TARGET)/common-lib -jni -o $@ org.sqlite.core.NativeDB

test:
	mvn test

clean: clean-native clean-java clean-tests


$(SQLITE_OUT)/sqlite3.o : $(SQLITE_UNPACKED)
	@mkdir -p $(@D)
	perl -p -e "s/sqlite3_api;/sqlite3_api = 0;/g" \
	    $(SQLITE_AMAL_DIR)/sqlite3ext.h > $(SQLITE_OUT)/sqlite3ext.h
# insert a code for loading extension functions
	perl -p -e "s/^opendb_out:/  if(!db->mallocFailed && rc==SQLITE_OK){ rc = RegisterExtensionFunctions(db); }\nopendb_out:/;" \
	    $(SQLITE_AMAL_DIR)/sqlite3.c > $(SQLITE_OUT)/sqlite3.c
	cat src/main/ext/*.c >> $(SQLITE_OUT)/sqlite3.c
	$(CC) -o $@ -c $(CCFLAGS) \
	    -DSQLITE_ENABLE_LOAD_EXTENSION=1 \
	    -DSQLITE_HAVE_ISNAN \
	    -DSQLITE_HAVE_USLEEP \
	    -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT \
	    -DSQLITE_ENABLE_COLUMN_METADATA \
	    -DSQLITE_CORE \
	    -DSQLITE_ENABLE_FTS3 \
	    -DSQLITE_ENABLE_FTS3_PARENTHESIS \
	    -DSQLITE_ENABLE_FTS5 \
	    -DSQLITE_ENABLE_JSON1 \
	    -DSQLITE_ENABLE_RTREE \
	    -DSQLITE_ENABLE_STAT2 \
	    -DSQLITE_THREADSAFE=1 \
	    -DSQLITE_DEFAULT_MEMSTATUS=0 \
	    -DSQLITE_MAX_VARIABLE_NUMBER=250000 \
	    $(SQLITE_FLAGS) \
	    $(SQLITE_OUT)/sqlite3.c

$(SQLITE_OUT)/$(LIBNAME): $(SQLITE_OUT)/sqlite3.o $(SRC)/org/sqlite/core/NativeDB.c
	@mkdir -p $(@D)
	$(CC) $(CCFLAGS) -I $(TARGET)/common-lib -c -o $(SQLITE_OUT)/NativeDB.o $(SRC)/org/sqlite/core/NativeDB.c
	$(CC) $(CCFLAGS) -o $@ $(SQLITE_OUT)/*.o $(LINKFLAGS)
	$(STRIP) $@


NATIVE_DIR=src/main/resources/org/sqlite/native/$(OS_NAME)/$(OS_ARCH)
NATIVE_TARGET_DIR:=$(TARGET)/classes/org/sqlite/native/$(OS_NAME)/$(OS_ARCH)
NATIVE_DLL:=$(NATIVE_DIR)/$(LIBNAME)

# For cross-compilation, install docker. See also https://github.com/dockcross/dockcross
native-all: native 

native: $(SQLITE_UNPACKED) $(NATIVE_DLL)

$(NATIVE_DLL): $(SQLITE_OUT)/$(LIBNAME)
	@mkdir -p $(@D)
	cp $< $@
	@mkdir -p $(NATIVE_TARGET_DIR)
	cp $< $(NATIVE_TARGET_DIR)/$(LIBNAME)

win32: $(SQLITE_UNPACKED) jni-header
	./docker/dockcross-windows-x86 bash -c 'make clean-native native CROSS_PREFIX=i686-w64-mingw32.static- OS_NAME=Windows OS_ARCH=x86'

win64: $(SQLITE_UNPACKED) jni-header
	./docker/dockcross-windows-x64 bash -c 'make clean-native native CROSS_PREFIX=x86_64-w64-mingw32.static- OS_NAME=Windows OS_ARCH=x86_64'

linux32: $(SQLITE_UNPACKED) jni-header
	docker run -ti -v $$PWD:/work xerial/centos5-linux-x86 bash -c 'make clean-native native OS_NAME=Linux OS_ARCH=x86'

linux64: $(SQLITE_UNPACKED) jni-header
	docker run -ti -v $$PWD:/work xerial/centos5-linux-x86_64 bash -c 'make clean-native native OS_NAME=Linux OS_ARCH=x86_64'

linux-arm: $(SQLITE_UNPACKED) jni-header
	./docker/dockcross-armv5 bash -c 'make clean-native native CROSS_PREFIX=arm-linux-gnueabi- OS_NAME=Linux OS_ARCH=arm'

linux-armhf: $(SQLITE_UNPACKED) jni-header
	./docker/dockcross-armv6 bash -c 'make clean-native native CROSS_PREFIX=arm-linux-gnueabihf- OS_NAME=Linux OS_ARCH=armhf'

sparcv9:
	$(MAKE) native OS_NAME=SunOS OS_ARCH=sparcv9

# deprecated
mac32:
	$(MAKE) native OS_NAME=Mac OS_ARCH=x86

package: native-all
	rm -rf target/dependency-maven-plugin-markers
	$(MVN) package

clean-native:
	rm -rf $(SQLITE_OUT)

clean-java:
	rm -rf $(TARGET)/*classes
	rm -rf $(TARGET)/sqlite-jdbc-*jar

clean-tests:
	rm -rf $(TARGET)/{surefire*,testdb.jar*}

docker-linux64:
	docker build -f docker/Dockerfile.linux_x86_64 -t xerial/centos5-linux-x86-64 .

docker-linux32:
	docker build -f docker/Dockerfile.linux_x86 -t xerial/centos5-linux-x86 .
