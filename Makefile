INPREFIX=
OUTDIR=builds
OUTPREFIX=

default: buildandupload

# Device output file
$(OUTDIR)/$(OUTPREFIX)device.nut: device-build

# Agent output file
$(OUTDIR)/$(OUTPREFIX)agent.nut: agent-build

# Build device code
device-build:
	mkdir -p $(OUTDIR)
	pleasebuild $(INPREFIX)device.nut > $(OUTDIR)/$(OUTPREFIX)device.nut

# Build agent code
agent-build:
	mkdir -p $(OUTDIR)
	pleasebuild $(INPREFIX)agent.nut > $(OUTDIR)/$(OUTPREFIX)agent.nut

# Build code
build: device-build agent-build

# Upload code
upload: builds/device.nut builds/agent.nut
	impt build run

# Build and upload code, the default
buildandupload: build upload

clean:
	rm $(OUTDIR)/$(OUTPREFIX){device,agent}.nut
