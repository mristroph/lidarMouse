/*!
  \file
  \brief ƒVƒŠƒAƒ‹—p‚Ì•â•ŠÖ”

  \author Satofumi KAMIMURA

  $Id: urg_serial_utils.c,v 0caa22c18f6b 2010/12/30 03:36:32 Satofumi $
*/

#include "urg_serial_utils.h"
#include "urg_detect_os.h"


#if defined(URG_WINDOWS_OS)
#include "urg_serial_utils_windows.c"
#else
#include "urg_serial_utils_linux.c"
#endif
