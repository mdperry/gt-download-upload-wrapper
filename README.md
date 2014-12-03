gt-download-upload-wrapper
===================

#Description

This tool is used to monitor and make gt-download and upload ore robust. 

To be use primarily with the PanCancer project.

Contained are two modules one for each uploading and downloading


#Usage

##Sample Upload

   GNOS::Upload->run_upload($command, $metadata_file);

##Sample Download

   GNOS::Download_>run_download($command, $file_name);


Feel free to use these modules in your own scripts.

Currently they are intended to be used in both the BWA and VCF SeqWare Workflows for the PanCancer Project
