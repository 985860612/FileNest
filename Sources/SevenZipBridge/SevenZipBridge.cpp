// Client7z.cpp

#include "StdAfx.h"

#include <stdio.h>
#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include "SevenZipBridge.h"

#include "../../../Common/MyWindows.h"
#include "../../../Common/MyInitGuid.h"

#include "../../../Common/Defs.h"
#include "../../../Common/IntToString.h"
#include "../../../Common/StringConvert.h"
#include "../../../Common/UTFConvert.h"

#include "../../../Windows/DLL.h"
#include "../../../Windows/FileDir.h"
#include "../../../Windows/FileFind.h"
#include "../../../Windows/FileName.h"
#include "../../../Windows/NtCheck.h"
#include "../../../Windows/PropVariant.h"
#include "../../../Windows/PropVariantConv.h"

#include "../../Common/FileStreams.h"

#include "../../Archive/IArchive.h"

#if 0
// for password request functions:
#include "../../UI/Console/UserInputUtils.h"
#endif

#include "../../IPassword.h"
#include "../../../../C/7zVersion.h"

#ifdef _WIN32
extern
HINSTANCE g_hInstance;
HINSTANCE g_hInstance = NULL;
#endif

Z7_DIAGNOSTIC_IGNORE_CAST_FUNCTION

// You can find full list of all GUIDs supported by 7-Zip in Guid.txt file.
// 7z format GUID: {23170F69-40C1-278A-1000-000110070000}

#define DEFINE_GUID_ARC(name, id) Z7_DEFINE_GUID(name, \
  0x23170F69, 0x40C1, 0x278A, 0x10, 0x00, 0x00, 0x01, 0x10, id, 0x00, 0x00);

enum
{
  kId_Zip = 1,
  kId_BZip2 = 2,
  kId_7z = 7,
  kId_Xz = 0xC,
  kId_Tar = 0xEE,
  kId_GZip = 0xEF
};

// use another id, if you want to support other formats (zip, Xz, ...).
// DEFINE_GUID_ARC (CLSID_Format, kId_Zip)
// DEFINE_GUID_ARC (CLSID_Format, kId_BZip2)
// DEFINE_GUID_ARC (CLSID_Format, kId_Xz)
// DEFINE_GUID_ARC (CLSID_Format, kId_Tar)
// DEFINE_GUID_ARC (CLSID_Format, kId_GZip)
DEFINE_GUID_ARC (CLSID_Format, kId_7z)

DEFINE_GUID_ARC (CLSID_Format_Zip, kId_Zip)
DEFINE_GUID_ARC (CLSID_Format_BZip2, kId_BZip2)
DEFINE_GUID_ARC (CLSID_Format_Rar, 3)
DEFINE_GUID_ARC (CLSID_Format_7z, kId_7z)
DEFINE_GUID_ARC (CLSID_Format_Xz, kId_Xz)
DEFINE_GUID_ARC (CLSID_Format_Rar5, 0xCC)
DEFINE_GUID_ARC (CLSID_Format_Tar, kId_Tar)
DEFINE_GUID_ARC (CLSID_Format_GZip, kId_GZip)

static thread_local std::string g_LastError;

static void SetLastError(const std::string &message)
{
  g_LastError = message;
}

using namespace NWindows;
using namespace NFile;
using namespace NDir;

#ifdef _WIN32
#define kDllName "7z.dll"
#else
#define kDllName "7z.so"
#endif

static const char * const kCopyrightString =
  "\n"
  "7-Zip"
  " (" kDllName " client)"
  " " MY_VERSION
  " : " MY_COPYRIGHT_DATE
  "\n";

static const char * const kHelpString =
"Usage: 7zcl.exe [a | l | x] archive.7z [fileName ...]\n"
"Examples:\n"
"  7zcl.exe a archive.7z f1.txt f2.txt  : compress two files to archive.7z\n"
"  7zcl.exe l archive.7z   : List contents of archive.7z\n"
"  7zcl.exe x archive.7z   : eXtract files from archive.7z\n";


static void Convert_UString_to_AString(const UString &s, AString &temp)
{
  int codePage = CP_OEMCP;
  /*
  int g_CodePage = -1;
  int codePage = g_CodePage;
  if (codePage == -1)
    codePage = CP_OEMCP;
  if (codePage == CP_UTF8)
    ConvertUnicodeToUTF8(s, temp);
  else
  */
    UnicodeStringToMultiByte2(temp, s, (UINT)codePage);
}

static FString CmdStringToFString(const char *s)
{
  return us2fs(GetUnicodeString(s));
}

static void Print(const char *s)
{
  fputs(s, stdout);
}

static void Print(const AString &s)
{
  Print(s.Ptr());
}

static void Print(const UString &s)
{
  AString as;
  Convert_UString_to_AString(s, as);
  Print(as);
}

static void Print(const wchar_t *s)
{
  Print(UString(s));
}

static void PrintNewLine()
{
  Print("\n");
}

static void PrintStringLn(const char *s)
{
  Print(s);
  PrintNewLine();
}

static void PrintError(const char *message)
{
  Print("Error: ");
  PrintNewLine();
  Print(message);
  PrintNewLine();
}

static void PrintError(const char *message, const FString &name)
{
  PrintError(message);
  Print(name);
}


static HRESULT IsArchiveItemProp(IInArchive *archive, UInt32 index, PROPID propID, bool &result)
{
  NCOM::CPropVariant prop;
  RINOK(archive->GetProperty(index, propID, &prop))
  if (prop.vt == VT_BOOL)
    result = VARIANT_BOOLToBool(prop.boolVal);
  else if (prop.vt == VT_EMPTY)
    result = false;
  else
    return E_FAIL;
  return S_OK;
}

static HRESULT IsArchiveItemFolder(IInArchive *archive, UInt32 index, bool &result)
{
  return IsArchiveItemProp(archive, index, kpidIsDir, result);
}


static const wchar_t * const kEmptyFileAlias = L"[Content]";


//////////////////////////////////////////////////////////////
// Archive Open callback class


class CArchiveOpenCallback Z7_final:
  public IArchiveOpenCallback,
  public ICryptoGetTextPassword,
  public CMyUnknownImp
{
  Z7_IFACES_IMP_UNK_2(IArchiveOpenCallback, ICryptoGetTextPassword)
public:

  bool PasswordIsDefined;
  UString Password;

  CArchiveOpenCallback() : PasswordIsDefined(false) {}
};

Z7_COM7F_IMF(CArchiveOpenCallback::SetTotal(const UInt64 * /* files */, const UInt64 * /* bytes */))
{
  return S_OK;
}

Z7_COM7F_IMF(CArchiveOpenCallback::SetCompleted(const UInt64 * /* files */, const UInt64 * /* bytes */))
{
  return S_OK;
}
  
Z7_COM7F_IMF(CArchiveOpenCallback::CryptoGetTextPassword(BSTR *password))
{
  if (!PasswordIsDefined)
  {
    // You can ask real password here from user
#if 0
    RINOK(GetPassword_HRESULT(&g_StdOut, Password))
    PasswordIsDefined = true;
#else
    PrintError("Password is not defined");
    return E_ABORT;
#endif
  }
  return StringToBstr(Password, password);
}



static const char * const kIncorrectCommand = "incorrect command";

//////////////////////////////////////////////////////////////
// Archive Extracting callback class

static const char * const kTestingString    =  "Testing     ";
static const char * const kExtractingString =  "Extracting  ";
static const char * const kSkippingString   =  "Skipping    ";
static const char * const kReadingString    =  "Reading     ";

static const char * const kUnsupportedMethod = "Unsupported Method";
static const char * const kCRCFailed = "CRC Failed";
static const char * const kDataError = "Data Error";
static const char * const kUnavailableData = "Unavailable data";
static const char * const kUnexpectedEnd = "Unexpected end of data";
static const char * const kDataAfterEnd = "There are some data after the end of the payload data";
static const char * const kIsNotArc = "Is not archive";
static const char * const kHeadersError = "Headers Error";


struct CArcTime
{
  FILETIME FT;
  UInt16 Prec;
  Byte Ns100;
  bool Def;

  CArcTime()
  {
    Clear();
  }

  void Clear()
  {
    FT.dwHighDateTime = FT.dwLowDateTime = 0;
    Prec = 0;
    Ns100 = 0;
    Def = false;
  }

  bool IsZero() const
  {
    return FT.dwLowDateTime == 0 && FT.dwHighDateTime == 0 && Ns100 == 0;
  }

  int GetNumDigits() const
  {
    if (Prec == k_PropVar_TimePrec_Unix ||
        Prec == k_PropVar_TimePrec_DOS)
      return 0;
    if (Prec == k_PropVar_TimePrec_HighPrec)
      return 9;
    if (Prec == k_PropVar_TimePrec_0)
      return 7;
    int digits = (int)Prec - (int)k_PropVar_TimePrec_Base;
    if (digits < 0)
      digits = 0;
    return digits;
  }

  void Write_To_FiTime(CFiTime &dest) const
  {
   #ifdef _WIN32
    dest = FT;
   #else
    if (FILETIME_To_timespec(FT, dest))
    if ((Prec == k_PropVar_TimePrec_Base + 8 ||
         Prec == k_PropVar_TimePrec_Base + 9)
        && Ns100 != 0)
    {
      dest.tv_nsec += Ns100;
    }
   #endif
  }

  void Set_From_Prop(const PROPVARIANT &prop)
  {
    FT = prop.filetime;
    unsigned prec = 0;
    unsigned ns100 = 0;
    const unsigned prec_Temp = prop.wReserved1;
    if (prec_Temp != 0
        && prec_Temp <= k_PropVar_TimePrec_1ns
        && prop.wReserved3 == 0)
    {
      const unsigned ns100_Temp = prop.wReserved2;
      if (ns100_Temp < 100)
      {
        ns100 = ns100_Temp;
        prec = prec_Temp;
      }
    }
    Prec = (UInt16)prec;
    Ns100 = (Byte)ns100;
    Def = true;
  }
};



class CArchiveExtractCallback Z7_final:
  public IArchiveExtractCallback,
  public ICryptoGetTextPassword,
  public CMyUnknownImp
{
  Z7_IFACES_IMP_UNK_2(IArchiveExtractCallback, ICryptoGetTextPassword)
  Z7_IFACE_COM7_IMP(IProgress)

  CMyComPtr<IInArchive> _archiveHandler;
  FString _directoryPath;  // Output directory
  UString _filePath;       // name inside arcvhive
  FString _diskFilePath;   // full path to file on disk
  bool _extractMode;
  struct CProcessedFileInfo
  {
    CArcTime MTime;
    UInt32 Attrib;
    bool isDir;
    bool Attrib_Defined;
  } _processedFileInfo;

  COutFileStream *_outFileStreamSpec;
  CMyComPtr<ISequentialOutStream> _outFileStream;

public:
  void Init(IInArchive *archiveHandler, const FString &directoryPath);

  UInt64 NumErrors;
  UInt64 TotalSize;
  bool PasswordIsDefined;
  UString Password;
  SZProgressCallback Progress;
  SZCancelCallback ShouldCancel;
  void *Context;

  CArchiveExtractCallback():
      TotalSize(0),
      PasswordIsDefined(false),
      Progress(NULL),
      ShouldCancel(NULL),
      Context(NULL) {}
};

void CArchiveExtractCallback::Init(IInArchive *archiveHandler, const FString &directoryPath)
{
  NumErrors = 0;
  _archiveHandler = archiveHandler;
  _directoryPath = directoryPath;
  NName::NormalizeDirPathPrefix(_directoryPath);
}

Z7_COM7F_IMF(CArchiveExtractCallback::SetTotal(UInt64 size))
{
  TotalSize = size;
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallback::SetCompleted(const UInt64 *completeValue))
{
  if (ShouldCancel && ShouldCancel(Context))
    return E_ABORT;
  if (Progress && completeValue)
    Progress(*completeValue, TotalSize, NULL, Context);
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallback::GetStream(UInt32 index,
    ISequentialOutStream **outStream, Int32 askExtractMode))
{
  *outStream = NULL;
  _outFileStream.Release();

  {
    // Get Name
    NCOM::CPropVariant prop;
    RINOK(_archiveHandler->GetProperty(index, kpidPath, &prop))
    
    UString fullPath;
    if (prop.vt == VT_EMPTY)
      fullPath = kEmptyFileAlias;
    else
    {
      if (prop.vt != VT_BSTR)
        return E_FAIL;
      fullPath = prop.bstrVal;
    }
    _filePath = fullPath;
  }

  // Never allow an archive entry to escape the selected destination.
  if (_filePath.IsEmpty() || _filePath[0] == L'/' || _filePath[0] == L'\\')
  {
    SetLastError("Archive contains an absolute or empty path");
    return E_ABORT;
  }
  {
    UString component;
    for (unsigned i = 0; i <= _filePath.Len(); i++)
    {
      const wchar_t c = i < _filePath.Len() ? _filePath[i] : L'/';
      if (c == L'/' || c == L'\\')
      {
        if (component == L"..")
        {
          SetLastError("Archive contains a parent-directory path");
          return E_ABORT;
        }
        component.Empty();
      }
      else
        component += c;
    }
  }

  if (askExtractMode != NArchive::NExtract::NAskMode::kExtract)
    return S_OK;

  {
    // Get Attrib
    NCOM::CPropVariant prop;
    RINOK(_archiveHandler->GetProperty(index, kpidAttrib, &prop))
    if (prop.vt == VT_EMPTY)
    {
      _processedFileInfo.Attrib = 0;
      _processedFileInfo.Attrib_Defined = false;
    }
    else
    {
      if (prop.vt != VT_UI4)
        return E_FAIL;
      _processedFileInfo.Attrib = prop.ulVal;
      _processedFileInfo.Attrib_Defined = true;
    }
  }

  RINOK(IsArchiveItemFolder(_archiveHandler, index, _processedFileInfo.isDir))

  {
    _processedFileInfo.MTime.Clear();
    // Get Modified Time
    NCOM::CPropVariant prop;
    RINOK(_archiveHandler->GetProperty(index, kpidMTime, &prop))
    switch (prop.vt)
    {
      case VT_EMPTY:
        // _processedFileInfo.MTime = _utcMTimeDefault;
        break;
      case VT_FILETIME:
        _processedFileInfo.MTime.Set_From_Prop(prop);
        break;
      default:
        return E_FAIL;
    }

  }
  {
    // Get Size
    NCOM::CPropVariant prop;
    RINOK(_archiveHandler->GetProperty(index, kpidSize, &prop))
    UInt64 newFileSize;
    /* bool newFileSizeDefined = */ ConvertPropVariantToUInt64(prop, newFileSize);
  }

  
  {
    // Create folders for file
    int slashPos = _filePath.ReverseFind_PathSepar();
    if (slashPos >= 0)
      CreateComplexDir(_directoryPath + us2fs(_filePath.Left(slashPos)));
  }

  FString fullProcessedPath = _directoryPath + us2fs(_filePath);
  _diskFilePath = fullProcessedPath;

  if (_processedFileInfo.isDir)
  {
    CreateComplexDir(fullProcessedPath);
  }
  else
  {
    NFind::CFileInfo fi;
    if (fi.Find(fullProcessedPath))
    {
      if (!DeleteFileAlways(fullProcessedPath))
      {
        PrintError("Cannot delete output file", fullProcessedPath);
        return E_ABORT;
      }
    }
    
    _outFileStreamSpec = new COutFileStream;
    CMyComPtr<ISequentialOutStream> outStreamLoc(_outFileStreamSpec);
    if (!_outFileStreamSpec->Create_ALWAYS(fullProcessedPath))
    {
      PrintError("Cannot open output file", fullProcessedPath);
      return E_ABORT;
    }
    _outFileStream = outStreamLoc;
    *outStream = outStreamLoc.Detach();
  }
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallback::PrepareOperation(Int32 askExtractMode))
{
  if (ShouldCancel && ShouldCancel(Context))
    return E_ABORT;
  _extractMode = false;
  switch (askExtractMode)
  {
    case NArchive::NExtract::NAskMode::kExtract:  _extractMode = true; break;
  }
  switch (askExtractMode)
  {
    case NArchive::NExtract::NAskMode::kExtract:  Print(kExtractingString); break;
    case NArchive::NExtract::NAskMode::kTest:  Print(kTestingString); break;
    case NArchive::NExtract::NAskMode::kSkip:  Print(kSkippingString); break;
    case NArchive::NExtract::NAskMode::kReadExternal: Print(kReadingString); break;
    default:
      Print("??? "); break;
  }
  Print(_filePath);
  if (Progress)
  {
    AString utf8;
    ConvertUnicodeToUTF8(_filePath, utf8);
    Progress(0, TotalSize, utf8.Ptr(), Context);
  }
  return S_OK;
}

Z7_COM7F_IMF(CArchiveExtractCallback::SetOperationResult(Int32 operationResult))
{
  switch (operationResult)
  {
    case NArchive::NExtract::NOperationResult::kOK:
      break;
    default:
    {
      NumErrors++;
      Print("  :  ");
      const char *s = NULL;
      switch (operationResult)
      {
        case NArchive::NExtract::NOperationResult::kUnsupportedMethod:
          s = kUnsupportedMethod;
          break;
        case NArchive::NExtract::NOperationResult::kCRCError:
          s = kCRCFailed;
          break;
        case NArchive::NExtract::NOperationResult::kDataError:
          s = kDataError;
          break;
        case NArchive::NExtract::NOperationResult::kUnavailable:
          s = kUnavailableData;
          break;
        case NArchive::NExtract::NOperationResult::kUnexpectedEnd:
          s = kUnexpectedEnd;
          break;
        case NArchive::NExtract::NOperationResult::kDataAfterEnd:
          s = kDataAfterEnd;
          break;
        case NArchive::NExtract::NOperationResult::kIsNotArc:
          s = kIsNotArc;
          break;
        case NArchive::NExtract::NOperationResult::kHeadersError:
          s = kHeadersError;
          break;
      }
      if (s)
      {
        Print("Error : ");
        Print(s);
      }
      else
      {
        char temp[16];
        ConvertUInt32ToString((UInt32)operationResult, temp);
        Print("Error #");
        Print(temp);
      }
    }
  }

  if (_outFileStream)
  {
    if (_processedFileInfo.MTime.Def)
    {
      CFiTime ft;
      _processedFileInfo.MTime.Write_To_FiTime(ft);
      _outFileStreamSpec->SetMTime(&ft);
    }
    RINOK(_outFileStreamSpec->Close())
  }
  _outFileStream.Release();
  if (_extractMode && _processedFileInfo.Attrib_Defined)
    SetFileAttrib_PosixHighDetect(_diskFilePath, _processedFileInfo.Attrib);
  PrintNewLine();
  return S_OK;
}


Z7_COM7F_IMF(CArchiveExtractCallback::CryptoGetTextPassword(BSTR *password))
{
  if (!PasswordIsDefined)
  {
#if 0
    // You can ask real password here from user
    RINOK(GetPassword_HRESULT(&g_StdOut, Password))
    PasswordIsDefined = true;
#else
    PrintError("Password is not defined");
    return E_ABORT;
#endif
  }
  return StringToBstr(Password, password);
}



//////////////////////////////////////////////////////////////
// Archive Creating callback class

struct CDirItem: public NWindows::NFile::NFind::CFileInfoBase
{
  UString Path_For_Handler;
  FString FullPath; // for filesystem

  CDirItem(const NWindows::NFile::NFind::CFileInfo &fi):
      CFileInfoBase(fi)
    {}
};

class CArchiveUpdateCallback Z7_final:
  public IArchiveUpdateCallback2,
  public ICryptoGetTextPassword2,
  public CMyUnknownImp
{
  Z7_IFACES_IMP_UNK_2(IArchiveUpdateCallback2, ICryptoGetTextPassword2)
  Z7_IFACE_COM7_IMP(IProgress)
  Z7_IFACE_COM7_IMP(IArchiveUpdateCallback)

public:
  CRecordVector<UInt64> VolumesSizes;
  UString VolName;
  UString VolExt;

  FString DirPrefix;
  const CObjectVector<CDirItem> *DirItems;

  bool PasswordIsDefined;
  UString Password;
  bool AskPassword;
  UInt64 TotalSize;
  SZProgressCallback Progress;
  SZCancelCallback ShouldCancel;
  void *Context;

  bool m_NeedBeClosed;

  FStringVector FailedFiles;
  CRecordVector<HRESULT> FailedCodes;

  CArchiveUpdateCallback():
      DirItems(NULL),
      PasswordIsDefined(false),
      AskPassword(false),
      TotalSize(0),
      Progress(NULL),
      ShouldCancel(NULL),
      Context(NULL)
      {}

  ~CArchiveUpdateCallback() { Finilize(); }
  HRESULT Finilize();

  void Init(const CObjectVector<CDirItem> *dirItems)
  {
    DirItems = dirItems;
    m_NeedBeClosed = false;
    FailedFiles.Clear();
    FailedCodes.Clear();
  }
};

Z7_COM7F_IMF(CArchiveUpdateCallback::SetTotal(UInt64 size))
{
  TotalSize = size;
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::SetCompleted(const UInt64 *completeValue))
{
  if (ShouldCancel && ShouldCancel(Context))
    return E_ABORT;
  if (Progress && completeValue)
    Progress(*completeValue, TotalSize, NULL, Context);
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetUpdateItemInfo(UInt32 /* index */,
      Int32 *newData, Int32 *newProperties, UInt32 *indexInArchive))
{
  if (newData)
    *newData = BoolToInt(true);
  if (newProperties)
    *newProperties = BoolToInt(true);
  if (indexInArchive)
    *indexInArchive = (UInt32)(Int32)-1;
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetProperty(UInt32 index, PROPID propID, PROPVARIANT *value))
{
  NCOM::CPropVariant prop;
  
  if (propID == kpidIsAnti)
  {
    prop = false;
    prop.Detach(value);
    return S_OK;
  }

  {
    const CDirItem &di = (*DirItems)[index];
    switch (propID)
    {
      case kpidPath:  prop = di.Path_For_Handler; break;
      case kpidIsDir:  prop = di.IsDir(); break;
      case kpidSize:  prop = di.Size; break;
      case kpidCTime:  PropVariant_SetFrom_FiTime(prop, di.CTime); break;
      case kpidATime:  PropVariant_SetFrom_FiTime(prop, di.ATime); break;
      case kpidMTime:  PropVariant_SetFrom_FiTime(prop, di.MTime); break;
      case kpidAttrib:  prop = (UInt32)di.GetWinAttrib(); break;
      case kpidPosixAttrib: prop = (UInt32)di.GetPosixAttrib(); break;
    }
  }
  prop.Detach(value);
  return S_OK;
}

HRESULT CArchiveUpdateCallback::Finilize()
{
  if (m_NeedBeClosed)
  {
    PrintNewLine();
    m_NeedBeClosed = false;
  }
  return S_OK;
}

static void GetStream2(const wchar_t *name)
{
  Print("Compressing  ");
  if (name[0] == 0)
    name = kEmptyFileAlias;
  Print(name);
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetStream(UInt32 index, ISequentialInStream **inStream))
{
  if (ShouldCancel && ShouldCancel(Context))
    return E_ABORT;
  RINOK(Finilize())

  const CDirItem &dirItem = (*DirItems)[index];
  GetStream2(dirItem.Path_For_Handler);
  if (Progress)
  {
    AString utf8;
    ConvertUnicodeToUTF8(dirItem.Path_For_Handler, utf8);
    Progress(0, TotalSize, utf8.Ptr(), Context);
  }
 
  if (dirItem.IsDir())
    return S_OK;

  {
    CInFileStream *inStreamSpec = new CInFileStream;
    CMyComPtr<ISequentialInStream> inStreamLoc(inStreamSpec);
    FString path = DirPrefix + dirItem.FullPath;
    if (!inStreamSpec->Open(path))
    {
      const DWORD sysError = ::GetLastError();
      FailedCodes.Add(HRESULT_FROM_WIN32(sysError));
      FailedFiles.Add(path);
      // if (systemError == ERROR_SHARING_VIOLATION)
      {
        PrintNewLine();
        PrintError("WARNING: can't open file");
        // Print(NError::MyFormatMessageW(systemError));
        return S_FALSE;
      }
      // return sysError;
    }
    *inStream = inStreamLoc.Detach();
  }
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::SetOperationResult(Int32 /* operationResult */))
{
  m_NeedBeClosed = true;
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetVolumeSize(UInt32 index, UInt64 *size))
{
  if (VolumesSizes.Size() == 0)
    return S_FALSE;
  if (index >= (UInt32)VolumesSizes.Size())
    index = VolumesSizes.Size() - 1;
  *size = VolumesSizes[index];
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::GetVolumeStream(UInt32 index, ISequentialOutStream **volumeStream))
{
  wchar_t temp[16];
  ConvertUInt32ToString(index + 1, temp);
  UString res = temp;
  while (res.Len() < 2)
    res.InsertAtFront(L'0');
  UString fileName = VolName;
  fileName.Add_Dot();
  fileName += res;
  fileName += VolExt;
  COutFileStream *streamSpec = new COutFileStream;
  CMyComPtr<ISequentialOutStream> streamLoc(streamSpec);
  if (!streamSpec->Create_NEW(us2fs(fileName)))
    return GetLastError_noZero_HRESULT();
  *volumeStream = streamLoc.Detach();
  return S_OK;
}

Z7_COM7F_IMF(CArchiveUpdateCallback::CryptoGetTextPassword2(Int32 *passwordIsDefined, BSTR *password))
{
  if (!PasswordIsDefined)
  {
    if (AskPassword)
    {
#if 0
      RINOK(GetPassword_HRESULT(&g_StdOut, Password))
      PasswordIsDefined = true;
#else
      PrintError("Password is not defined");
      return E_ABORT;
#endif
    }
  }
  *passwordIsDefined = BoolToInt(PasswordIsDefined);
  return StringToBstr(Password, password);
}


// Main function

#if defined(_UNICODE) && !defined(_WIN64) && !defined(UNDER_CE)
#define NT_CHECK_FAIL_ACTION PrintError("Unsupported Windows version"); return 1;
#endif

int Z7_CDECL main(int numArgs, const char *args[])
{
  NT_CHECK

  #ifdef ENV_HAVE_LOCALE
  MY_SetLocale();
  #endif

  PrintStringLn(kCopyrightString);

  if (numArgs < 2)
  {
    PrintStringLn(kHelpString);
    return 0;
  }

  FString dllPrefix;

  #ifdef _WIN32
  dllPrefix = NDLL::GetModuleDirPrefix();
  #else
  {
    AString s (args[0]);
    int sep = s.ReverseFind_PathSepar();
    s.DeleteFrom(sep + 1);
    dllPrefix = s;
  }
  #endif

  NDLL::CLibrary lib;
  if (!lib.Load(dllPrefix + FTEXT(kDllName)))
  {
    PrintError("Cannot load 7-zip library");
    return 1;
  }

#if defined(__clang__)
#pragma GCC diagnostic ignored "-Wc++98-compat-pedantic"
#endif

#ifdef _WIN32
Z7_DIAGNOSTIC_IGNORE_CAST_FUNCTION
#endif

  Func_CreateObject
     f_CreateObject = Z7_GET_PROC_ADDRESS(
  Func_CreateObject, lib.Get_HMODULE(),
      "CreateObject");
  if (!f_CreateObject)
  {
    PrintError("Cannot get CreateObject");
    return 1;
  }

  char c = 0;
  UString password;
  bool passwordIsDefined = false;
  CObjectVector<FString> params;

  for (int curCmd = 1; curCmd < numArgs; curCmd++)
  {
    AString a(args[curCmd]);

    if (!a.IsEmpty())
    {
      if (a[0] == '-')
      {
        if (!passwordIsDefined && a[1] == 'p')
        {
          password = GetUnicodeString(a.Ptr(2));
          passwordIsDefined = true;
          continue;
        }
      }
      else
      {
        if (c)
        {
          params.Add(CmdStringToFString(a));
          continue;
        }
        if (a.Len() == 1)
        {
          c = (char)MyCharLower_Ascii(a[0]);
          continue;
        }
      }
    }
    {
      PrintError(kIncorrectCommand);
      return 1;
    }
  }

  if (!c || params.Size() < 1)
  {
    PrintError(kIncorrectCommand);
    return 1;
  }

  const FString &archiveName = params[0];
  
  if (c == 'a')
  {
    // create archive command
    if (params.Size() < 2)
    {
      PrintError(kIncorrectCommand);
      return 1;
    }
    CObjectVector<CDirItem> dirItems;
    {
      unsigned i;
      for (i = 1; i < params.Size(); i++)
      {
        const FString &name = params[i];
        
        NFind::CFileInfo fi;
        if (!fi.Find(name))
        {
          PrintError("Can't find file", name);
          return 1;
        }

        CDirItem di(fi);
        
        di.Path_For_Handler = fs2us(name);
        di.FullPath = name;
        dirItems.Add(di);
      }
    }

    COutFileStream *outFileStreamSpec = new COutFileStream;
    CMyComPtr<IOutStream> outFileStream = outFileStreamSpec;
    if (!outFileStreamSpec->Create_NEW(archiveName))
    {
      PrintError("can't create archive file");
      return 1;
    }

    CMyComPtr<IOutArchive> outArchive;
    if (f_CreateObject(&CLSID_Format, &IID_IOutArchive, (void **)&outArchive) != S_OK)
    {
      PrintError("Cannot get class object");
      return 1;
    }

    CArchiveUpdateCallback *updateCallbackSpec = new CArchiveUpdateCallback;
    CMyComPtr<IArchiveUpdateCallback2> updateCallback(updateCallbackSpec);
    updateCallbackSpec->Init(&dirItems);
    updateCallbackSpec->PasswordIsDefined = passwordIsDefined;
    updateCallbackSpec->Password = password;

    /*
    {
      const wchar_t *names[] =
      {
        L"m",
        L"s",
        L"x"
      };
      const unsigned kNumProps = Z7_ARRAY_SIZE(names);
      NCOM::CPropVariant values[kNumProps] =
      {
        L"lzma",
        false,    // solid mode OFF
        (UInt32)9 // compression level = 9 - ultra
      };
      CMyComPtr<ISetProperties> setProperties;
      outArchive->QueryInterface(IID_ISetProperties, (void **)&setProperties);
      if (!setProperties)
      {
        PrintError("ISetProperties unsupported");
        return 1;
      }
      if (setProperties->SetProperties(names, values, kNumProps) != S_OK)
      {
        PrintError("SetProperties() error");
        return 1;
      }
    }
    */
    
    HRESULT result = outArchive->UpdateItems(outFileStream, dirItems.Size(), updateCallback);
    
    updateCallbackSpec->Finilize();
    
    if (result != S_OK)
    {
      PrintError("Update Error");
      return 1;
    }
    
    FOR_VECTOR (i, updateCallbackSpec->FailedFiles)
    {
      PrintNewLine();
      PrintError("Error for file", updateCallbackSpec->FailedFiles[i]);
    }
    
    if (updateCallbackSpec->FailedFiles.Size() != 0)
      return 1;
  }
  else
  {
    if (params.Size() != 1)
    {
      PrintError(kIncorrectCommand);
      return 1;
    }

    bool listCommand;
    
    if (c == 'l')
      listCommand = true;
    else if (c == 'x')
      listCommand = false;
    else
    {
      PrintError(kIncorrectCommand);
      return 1;
    }
  
    CMyComPtr<IInArchive> archive;
    if (f_CreateObject(&CLSID_Format, &IID_IInArchive, (void **)&archive) != S_OK)
    {
      PrintError("Cannot get class object");
      return 1;
    }
    
    CInFileStream *fileSpec = new CInFileStream;
    CMyComPtr<IInStream> file = fileSpec;
    
    if (!fileSpec->Open(archiveName))
    {
      PrintError("Cannot open archive file", archiveName);
      return 1;
    }

    {
      CArchiveOpenCallback *openCallbackSpec = new CArchiveOpenCallback;
      CMyComPtr<IArchiveOpenCallback> openCallback(openCallbackSpec);
      openCallbackSpec->PasswordIsDefined = passwordIsDefined;
      openCallbackSpec->Password = password;
      
      const UInt64 scanSize = 1 << 23;
      if (archive->Open(file, &scanSize, openCallback) != S_OK)
      {
        PrintError("Cannot open file as archive", archiveName);
        return 1;
      }
    }
    
    if (listCommand)
    {
      // List command
      UInt32 numItems = 0;
      archive->GetNumberOfItems(&numItems);
      for (UInt32 i = 0; i < numItems; i++)
      {
        {
          // Get uncompressed size of file
          NCOM::CPropVariant prop;
          archive->GetProperty(i, kpidSize, &prop);
          char s[64];
          ConvertPropVariantToShortString(prop, s);
          Print(s);
          Print("  ");
        }
        {
          // Get name of file
          NCOM::CPropVariant prop;
          archive->GetProperty(i, kpidPath, &prop);
          if (prop.vt == VT_BSTR)
            Print(prop.bstrVal);
          else if (prop.vt != VT_EMPTY)
            Print("ERROR!");
        }
        PrintNewLine();
      }
    }
    else
    {
      // Extract command
      CArchiveExtractCallback *extractCallbackSpec = new CArchiveExtractCallback;
      CMyComPtr<IArchiveExtractCallback> extractCallback(extractCallbackSpec);
      extractCallbackSpec->Init(archive, FString()); // second parameter is output folder path
      extractCallbackSpec->PasswordIsDefined = passwordIsDefined;
      extractCallbackSpec->Password = password;

      /*
      const wchar_t *names[] =
      {
        L"mt",
        L"mtf"
      };
      const unsigned kNumProps = sizeof(names) / sizeof(names[0]);
      NCOM::CPropVariant values[kNumProps] =
      {
        (UInt32)1,
        false
      };
      CMyComPtr<ISetProperties> setProperties;
      archive->QueryInterface(IID_ISetProperties, (void **)&setProperties);
      if (setProperties)
      {
        if (setProperties->SetProperties(names, values, kNumProps) != S_OK)
        {
          PrintError("SetProperties() error");
          return 1;
        }
      }
      */

      HRESULT result = archive->Extract(NULL, (UInt32)(Int32)(-1), false, extractCallback);
  
      if (result != S_OK)
      {
        PrintError("Extract Error");
        return 1;
      }
    }
  }

  return 0;
}


// SevenZip Mac C ABI

static bool LoadCreateObject(const char *libraryPath,
    NDLL::CLibrary &library, Func_CreateObject &createObject)
{
  if (!libraryPath || !library.Load(CmdStringToFString(libraryPath)))
  {
    SetLastError("Cannot load the bundled 7-Zip library");
    return false;
  }
  createObject = Z7_GET_PROC_ADDRESS(
      Func_CreateObject, library.Get_HMODULE(), "CreateObject");
  if (!createObject)
  {
    SetLastError("The bundled 7-Zip library has no CreateObject export");
    return false;
  }
  return true;
}

static std::string LowerExtension(const char *path)
{
  std::string extension = std::filesystem::u8path(path).extension().u8string();
  std::transform(extension.begin(), extension.end(), extension.begin(),
      [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return extension;
}

static void AddCandidate(std::vector<const GUID *> &candidates, const GUID *value)
{
  if (std::find(candidates.begin(), candidates.end(), value) == candidates.end())
    candidates.push_back(value);
}

static std::vector<const GUID *> InputFormatCandidates(const char *archivePath)
{
  std::vector<const GUID *> candidates;
  const std::string extension = LowerExtension(archivePath);
  if (extension == ".7z") AddCandidate(candidates, &CLSID_Format_7z);
  else if (extension == ".zip") AddCandidate(candidates, &CLSID_Format_Zip);
  else if (extension == ".rar")
  {
    AddCandidate(candidates, &CLSID_Format_Rar5);
    AddCandidate(candidates, &CLSID_Format_Rar);
  }
  else if (extension == ".tar") AddCandidate(candidates, &CLSID_Format_Tar);
  else if (extension == ".gz" || extension == ".tgz") AddCandidate(candidates, &CLSID_Format_GZip);
  else if (extension == ".bz2" || extension == ".tbz2") AddCandidate(candidates, &CLSID_Format_BZip2);
  else if (extension == ".xz" || extension == ".txz") AddCandidate(candidates, &CLSID_Format_Xz);

  AddCandidate(candidates, &CLSID_Format_7z);
  AddCandidate(candidates, &CLSID_Format_Zip);
  AddCandidate(candidates, &CLSID_Format_Rar5);
  AddCandidate(candidates, &CLSID_Format_Rar);
  AddCandidate(candidates, &CLSID_Format_Tar);
  AddCandidate(candidates, &CLSID_Format_GZip);
  AddCandidate(candidates, &CLSID_Format_BZip2);
  AddCandidate(candidates, &CLSID_Format_Xz);
  return candidates;
}

static bool OpenInputArchive(Func_CreateObject createObject,
    const char *archivePath, const char *password,
    CMyComPtr<IInArchive> &archive, CMyComPtr<IInStream> &stream)
{
  for (const GUID *format : InputFormatCandidates(archivePath))
  {
    CMyComPtr<IInArchive> candidate;
    if (createObject(format, &IID_IInArchive, (void **)&candidate) != S_OK)
      continue;

    CInFileStream *fileSpec = new CInFileStream;
    CMyComPtr<IInStream> file = fileSpec;
    if (!fileSpec->Open(CmdStringToFString(archivePath)))
    {
      SetLastError("Cannot open the archive file");
      return false;
    }

    CArchiveOpenCallback *callbackSpec = new CArchiveOpenCallback;
    CMyComPtr<IArchiveOpenCallback> callback(callbackSpec);
    callbackSpec->PasswordIsDefined = password && password[0] != 0;
    if (callbackSpec->PasswordIsDefined)
      callbackSpec->Password = GetUnicodeString(password);
    const UInt64 scanSize = 1 << 23;
    if (candidate->Open(file, &scanSize, callback) == S_OK)
    {
      archive = candidate;
      stream = file;
      return true;
    }
  }
  SetLastError("Unsupported archive, damaged archive, or incorrect password");
  return false;
}

static bool AddDiskItem(CObjectVector<CDirItem> &items,
    const std::filesystem::path &diskPath, const std::string &archivePath)
{
  NFind::CFileInfo fileInfo;
  const std::string diskUtf8 = diskPath.u8string();
  if (!fileInfo.Find(CmdStringToFString(diskUtf8.c_str())))
  {
    SetLastError("A selected input disappeared before compression");
    return false;
  }
  CDirItem item(fileInfo);
  item.Path_For_Handler = GetUnicodeString(archivePath.c_str());
  item.FullPath = CmdStringToFString(diskUtf8.c_str());
  items.Add(item);
  return true;
}

static bool CollectDiskItems(const char *const *inputPaths, size_t inputCount,
    CObjectVector<CDirItem> &items)
{
  namespace fs = std::filesystem;
  try
  {
    for (size_t inputIndex = 0; inputIndex < inputCount; inputIndex++)
    {
      const fs::path input = fs::absolute(fs::u8path(inputPaths[inputIndex])).lexically_normal();
      if (!fs::exists(input))
      {
        SetLastError("A selected input does not exist");
        return false;
      }
      const fs::path base = input.parent_path();
      std::vector<fs::path> paths;
      paths.push_back(input);
      if (fs::is_directory(input) && !fs::is_symlink(input))
      {
        for (const fs::directory_entry &entry :
            fs::recursive_directory_iterator(input, fs::directory_options::skip_permission_denied))
        {
          if (!entry.is_symlink())
            paths.push_back(entry.path());
        }
      }
      std::sort(paths.begin(), paths.end());
      for (const fs::path &path : paths)
      {
        const std::string archived = fs::relative(path, base).generic_u8string();
        if (!AddDiskItem(items, path, archived))
          return false;
      }
    }
  }
  catch (const std::exception &error)
  {
    SetLastError(std::string("Cannot enumerate selected files: ") + error.what());
    return false;
  }
  return true;
}

static std::string JsonEscape(const std::string &value)
{
  std::string result;
  for (char sourceCharacter : value)
  {
    const unsigned char c = static_cast<unsigned char>(sourceCharacter);
    switch (c)
    {
      case '\\': result += "\\\\"; break;
      case '"': result += "\\\""; break;
      case '\n': result += "\\n"; break;
      case '\r': result += "\\r"; break;
      case '\t': result += "\\t"; break;
      default:
        if (c < 0x20)
        {
          char escaped[7];
          snprintf(escaped, sizeof(escaped), "\\u%04x", c);
          result += escaped;
        }
        else
          result += static_cast<char>(c);
    }
  }
  return result;
}

extern "C" const char *sz_version(void)
{
  return MY_VERSION;
}

extern "C" const char *sz_last_error(void)
{
  return g_LastError.c_str();
}

extern "C" int sz_extract(const char *libraryPath, const char *archivePath,
    const char *outputDirectory, const char *password,
    SZProgressCallback progress, SZCancelCallback shouldCancel, void *context)
{
  g_LastError.clear();
  if (!libraryPath || !archivePath || !outputDirectory)
  {
    SetLastError("Missing extraction argument");
    return 2;
  }
  try
  {
    namespace fs = std::filesystem;
    const fs::path destination = fs::u8path(outputDirectory);
    if (fs::exists(destination))
    {
      SetLastError("The extraction destination already exists");
      return 5;
    }
    const std::string suffix = ".partial-" + std::to_string(
        std::chrono::steady_clock::now().time_since_epoch().count());
    const fs::path partial = fs::u8path(std::string(outputDirectory) + suffix);
    NDLL::CLibrary library;
    Func_CreateObject createObject = NULL;
    if (!LoadCreateObject(libraryPath, library, createObject))
      return 3;
    CMyComPtr<IInArchive> archive;
    CMyComPtr<IInStream> stream;
    if (!OpenInputArchive(createObject, archivePath, password, archive, stream))
      return 4;
    const std::string partialUtf8 = partial.u8string();
    const FString output = CmdStringToFString(partialUtf8.c_str());
    if (!CreateComplexDir(output))
    {
      SetLastError("Cannot create the extraction destination");
      return 5;
    }
    CArchiveExtractCallback *callbackSpec = new CArchiveExtractCallback;
    CMyComPtr<IArchiveExtractCallback> callback(callbackSpec);
    callbackSpec->Init(archive, output);
    callbackSpec->PasswordIsDefined = password && password[0] != 0;
    if (callbackSpec->PasswordIsDefined)
      callbackSpec->Password = GetUnicodeString(password);
    callbackSpec->Progress = progress;
    callbackSpec->ShouldCancel = shouldCancel;
    callbackSpec->Context = context;
    const HRESULT result = archive->Extract(NULL, (UInt32)(Int32)(-1), false, callback);
    archive->Close();
    if (result == E_ABORT && shouldCancel && shouldCancel(context))
    {
      fs::remove_all(partial);
      SetLastError("Cancelled");
      return 6;
    }
    if (result != S_OK || callbackSpec->NumErrors != 0)
    {
      fs::remove_all(partial);
      if (g_LastError.empty()) SetLastError("7-Zip could not extract every item");
      return 7;
    }
    fs::rename(partial, destination);
    return 0;
  }
  catch (const std::exception &error)
  {
    SetLastError(error.what());
    return 8;
  }
  catch (...)
  {
    SetLastError("Unexpected 7-Zip extraction error");
    return 9;
  }
}

extern "C" int sz_compress(const char *libraryPath, const char *archivePath,
    const char *format, const char *const *inputPaths, size_t inputCount,
    const char *password, int compressionLevel,
    SZProgressCallback progress, SZCancelCallback shouldCancel, void *context)
{
  g_LastError.clear();
  if (!libraryPath || !archivePath || !format || !inputPaths || inputCount == 0)
  {
    SetLastError("Missing compression argument");
    return 2;
  }
  try
  {
    const GUID *formatId = NULL;
    const std::string formatName(format);
    if (formatName == "7z") formatId = &CLSID_Format_7z;
    else if (formatName == "zip") formatId = &CLSID_Format_Zip;
    else if (formatName == "tar") formatId = &CLSID_Format_Tar;
    else
    {
      SetLastError("Compression format must be 7z, zip, or tar");
      return 3;
    }
    namespace fs = std::filesystem;
    const fs::path destination = fs::u8path(archivePath);
    if (fs::exists(destination))
    {
      SetLastError("The destination archive already exists");
      return 4;
    }
    CObjectVector<CDirItem> items;
    if (!CollectDiskItems(inputPaths, inputCount, items))
      return 5;

    NDLL::CLibrary library;
    Func_CreateObject createObject = NULL;
    if (!LoadCreateObject(libraryPath, library, createObject))
      return 6;
    CMyComPtr<IOutArchive> archive;
    if (createObject(formatId, &IID_IOutArchive, (void **)&archive) != S_OK)
    {
      SetLastError("The selected format cannot be created by this 7-Zip build");
      return 7;
    }
    if (compressionLevel < 0) compressionLevel = 0;
    if (compressionLevel > 9) compressionLevel = 9;
    {
      const wchar_t *names[] = { L"x" };
      NCOM::CPropVariant values[] = { (UInt32)compressionLevel };
      CMyComPtr<ISetProperties> properties;
      archive->QueryInterface(IID_ISetProperties, (void **)&properties);
      if (properties && properties->SetProperties(names, values, 1) != S_OK)
      {
        SetLastError("7-Zip rejected the compression settings");
        return 8;
      }
    }

    const fs::path partial = fs::u8path(std::string(archivePath) + ".partial");
    fs::remove(partial);
    COutFileStream *outputSpec = new COutFileStream;
    CMyComPtr<IOutStream> output = outputSpec;
    if (!outputSpec->Create_NEW(CmdStringToFString(partial.u8string().c_str())))
    {
      SetLastError("Cannot create the destination archive");
      return 9;
    }
    CArchiveUpdateCallback *callbackSpec = new CArchiveUpdateCallback;
    CMyComPtr<IArchiveUpdateCallback2> callback(callbackSpec);
    callbackSpec->Init(&items);
    callbackSpec->PasswordIsDefined = password && password[0] != 0;
    if (callbackSpec->PasswordIsDefined)
      callbackSpec->Password = GetUnicodeString(password);
    callbackSpec->Progress = progress;
    callbackSpec->ShouldCancel = shouldCancel;
    callbackSpec->Context = context;
    const HRESULT result = archive->UpdateItems(output, items.Size(), callback);
    callbackSpec->Finilize();
    outputSpec->Close();
    output.Release();
    archive.Release();
    if (result != S_OK || callbackSpec->FailedFiles.Size() != 0)
    {
      fs::remove(partial);
      if (result == E_ABORT && shouldCancel && shouldCancel(context))
        SetLastError("Cancelled");
      else if (g_LastError.empty())
        SetLastError("7-Zip could not compress every selected item");
      return 10;
    }
    fs::rename(partial, destination);
    return 0;
  }
  catch (const std::exception &error)
  {
    SetLastError(error.what());
    return 11;
  }
  catch (...)
  {
    SetLastError("Unexpected 7-Zip compression error");
    return 12;
  }
}

extern "C" char *sz_list_json(const char *libraryPath, const char *archivePath,
    const char *password)
{
  g_LastError.clear();
  try
  {
    NDLL::CLibrary library;
    Func_CreateObject createObject = NULL;
    if (!LoadCreateObject(libraryPath, library, createObject))
      return NULL;
    CMyComPtr<IInArchive> archive;
    CMyComPtr<IInStream> stream;
    if (!OpenInputArchive(createObject, archivePath, password, archive, stream))
      return NULL;
    UInt32 count = 0;
    if (archive->GetNumberOfItems(&count) != S_OK)
    {
      SetLastError("Cannot read archive items");
      return NULL;
    }
    std::string json = "[";
    for (UInt32 index = 0; index < count; index++)
    {
      if (index != 0) json += ',';
      std::string path;
      NCOM::CPropVariant pathProperty;
      if (archive->GetProperty(index, kpidPath, &pathProperty) == S_OK &&
          pathProperty.vt == VT_BSTR)
      {
        AString utf8;
        ConvertUnicodeToUTF8(pathProperty.bstrVal, utf8);
        path = utf8.Ptr();
      }
      UInt64 size = 0;
      NCOM::CPropVariant sizeProperty;
      if (archive->GetProperty(index, kpidSize, &sizeProperty) == S_OK)
        ConvertPropVariantToUInt64(sizeProperty, size);
      bool directory = false;
      IsArchiveItemFolder(archive, index, directory);
      json += "{\"path\":\"" + JsonEscape(path) + "\",\"size\":" +
          std::to_string(size) + ",\"directory\":" +
          (directory ? "true" : "false") + "}";
    }
    json += ']';
    archive->Close();
    char *result = static_cast<char *>(malloc(json.size() + 1));
    if (!result)
    {
      SetLastError("Out of memory while listing archive");
      return NULL;
    }
    memcpy(result, json.c_str(), json.size() + 1);
    return result;
  }
  catch (const std::exception &error)
  {
    SetLastError(error.what());
    return NULL;
  }
  catch (...)
  {
    SetLastError("Unexpected 7-Zip listing error");
    return NULL;
  }
}

extern "C" void sz_free_string(char *value)
{
  free(value);
}
