//
// Copyright (C) 2007-2008 S&T, The Netherlands.
//
// This file is part of CODA.
//
// CODA is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// CODA is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with CODA; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//

%module codac
//%feature("autodoc","1")


%include "typemaps.i"
%include "cstring.i"
%include "coda_typemaps.i"


%{
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "numarray/libnumarray.h"
#include "numarray/arrayobject.h"
#include "coda.h"
%}


/*
    make sure to initialise libnumarray.
*/
%init %{
    import_libnumeric();
    import_libnumarray();
%}


/*
----------------------------------------------------------------------------------------
- CUSTOM EXCEPTION CLASS CREATION                                                      -
----------------------------------------------------------------------------------------
*/
/*
    create our own Exception class for all codac errors.
*/
%{
    static PyObject *codacError;
%}

%init %{
    codacError = PyErr_NewException("codac.CodacError",NULL,NULL);
    /*
        ensure we keep a reference, as PyModule_AddObject steals references.
    */
    Py_INCREF(codacError);
    PyModule_AddObject(m,"CodacError", codacError);
%}
    
/*
    tell SWIG about CodaError (SWIG will not parse the PyModule_AddObject()
    call. without the statement below, CodaError would only be accessible as
    codac._codac.CodaError.)
*/
%pythoncode %{
    CodacError = _codac.CodacError
%}


/*
----------------------------------------------------------------------------------------
- RENAME AND IGNORE                                                                    -
----------------------------------------------------------------------------------------
*/
/*
    include coda_rename.i. this is a long list of %rename directives
    to strip the 'coda_' part from the Python declarations.
    (see also: generate_coda_rename.sh)
*/
%include "coda_rename.i"


/*
    include coda_ignore.i. this is a long list of %ignore directives
    to ignore #define's that define a constant that should not be
    included in the Python module. currently #define's starting with
    'CODA_' and 'HAVE_' are ignored.
    (see also: generate_coda_ignore.sh)
*/
%include "coda_ignore.i"

/*
    declarations _not_ included in coda_ignore.i that nevertheless
    should be ignored. these declarations are related to error reporting,
    but this is handled through exceptions in Python.
*/
%ignore coda_errno;
%ignore coda_set_error;
%ignore coda_errno_to_string;


/*
----------------------------------------------------------------------------------------
- CUSTOM WRAPPERS AND HELPER FUNCTIONS THAT DO NOT NEED THE GLOBAL EXCEPTION MECHANISM -
----------------------------------------------------------------------------------------
*/
/*
    custom wrapper to expose global libcoda_version variable.
*/
%rename(version) _libcoda_version;
%inline
%{
const char *_libcoda_version()
{
    return libcoda_version;
}
%}
%ignore libcoda_version;


/*
    custom wrapper for coda_match_filefilter to allow a Python callback
    function.
*/
%apply (int COUNT, const char **INPUT_ARRAY) { (int num_filepaths, const char **filepathlist) };
%rename(match_filefilter)  coda_match_filefilter_helper;
%exception coda_match_filefilter_helper
{
    $action

    /*
        needed to ensure exceptions generated within coda_match_filefilter_helper or
        c_callback are correctly propagated to the Python interpreter. if omitted an
        exception will result in the following error:
        "Fatal Python error: unexpected exception during garbage collection"
    */
    if (PyErr_Occurred() != NULL)
    {
        return NULL;
    }
}

%{
    /*
        callback function in the C-domain, that acts as a proxy for the callback in the Python-domain.
        the Python callback function (a Python callable) is passed as userdata.
    */
    int c_callback(const char *filepath, coda_filefilter_status status, const char *error, void *userdata)
    {
        PyObject *py_result;

        py_result = PyObject_CallFunction((PyObject*) userdata, "sis", filepath, status, error);

        if (py_result == NULL)
        {
            return -1;
        }
        else
        {
            int result = -1;

            if (PyInt_Check(py_result))
            {
                result = (int)PyInt_AsLong(py_result);
            }

            Py_DECREF(py_result);
            return result;
        }
    }
%}

%inline
%{
    /*
        helper function to allow a callback in the Python-domain for coda_match_filefilter()
    */
    int coda_match_filefilter_helper( const char *filefilter, int num_filepaths, const char **filepathlist, PyObject *py_callback )
    {
        if (py_callback==NULL || !PyCallable_Check(py_callback))
        {
            PyErr_SetString(PyExc_TypeError, "callback argument must be callable");
            return -1;
        }
        else
        {
            return coda_match_filefilter(filefilter, num_filepaths, filepathlist, c_callback, (void*) py_callback);
        }
    }
%}
%ignore coda_match_filefilter;


/*
    custom wrapper for coda_Cursor. pointers to coda_Cursor structs are
    treated as pointers to an opaque type. the definitions below create
    a Cursor proxy class that has no attributes (i.e. the underlying C
    implementation is unreachable from Python). the proxy class allows
    expression in Python like:
    
        import codac
    
        #create new coda_Cursor
        cursor = codac.Cursor()  
        
        #make a deep copy of cursor
        import copy
        cursor2 = copy.deepcopy(cursor)
        
        #delete cursor (NOTE: also frees underlying coda_Cursor struct)
        del cursor
        
    Python takes ownership of the underlying coda_Cursor structs created
    through the constructor Cursor.__init__(), copy.copy(), or
    copy.deepcopy().
*/
/*
    %newobject ensures that Python will take ownership of the underlying
    C struct returned by __deepcopy__().
*/
%newobject coda_Cursor_struct::__deepcopy__;
%feature("shadow") coda_Cursor_struct::__deepcopy__
{
    def __deepcopy__(self,memo):
        return _codac.Cursor___deepcopy__(self)
}
%exception coda_Cursor_struct::__deepcopy__
{
    $action
    
    if (result == NULL)
    {
        return PyErr_NoMemory();
    }
}
%rename(Cursor) coda_Cursor_struct;
struct coda_Cursor_struct
{
    %extend
    {
        coda_Cursor_struct()
        {
            return (coda_Cursor *)malloc(sizeof(coda_Cursor));
        }
        
        ~coda_Cursor_struct()
        {
            free(self);
        }
        
        coda_Cursor *__deepcopy__()
        {
            coda_Cursor *new_cursor;

            new_cursor = (coda_Cursor *)malloc(sizeof(coda_Cursor));
            if( new_cursor != NULL )
            {
                memcpy(new_cursor, self, sizeof(coda_Cursor));
            }
            return new_cursor;
        }
    }

    %shadow
    %{
        def __copy__(self):
            return _codac.Cursor___deepcopy__(self)
    %}
};


/*
----------------------------------------------------------------------------------------
- GLOBAL TYPEMAP ASSIGNMENTS                                                           -
----------------------------------------------------------------------------------------
*/
/*
    in the following, all arguments starting with '*dst' refer to
    the coda_cursor_read_* functions.
*/
/*
    handle standard POSIX integral type output arguments.
*/
POSIX_SCALAR_OUTPUT_HELPER(int8_t, PyInt_FromLong)
POSIX_SCALAR_OUTPUT_HELPER(uint8_t, PyInt_FromLong)
POSIX_SCALAR_OUTPUT_HELPER(int16_t, PyInt_FromLong)
POSIX_SCALAR_OUTPUT_HELPER(uint16_t, PyInt_FromLong)
POSIX_SCALAR_OUTPUT_HELPER(int32_t, PyInt_FromLong)
POSIX_SCALAR_OUTPUT_HELPER(uint32_t, PyLong_FromUnsignedLong)
POSIX_SCALAR_OUTPUT_HELPER(int64_t, PyLong_FromLongLong)
POSIX_SCALAR_OUTPUT_HELPER(uint64_t, PyLong_FromUnsignedLongLong)

%apply int8_t *OUTPUT { int8_t *dst };
%apply uint8_t *OUTPUT { uint8_t *dst };
%apply int16_t *OUTPUT { int16_t *dst };
%apply uint16_t *OUTPUT { uint16_t *dst };
%apply int32_t *OUTPUT { int32_t *dst };
%apply uint32_t *OUTPUT { uint32_t *dst };
/*
    coda_get_product_file_size()::int64_t *file_size
    coda_get_product_variable_value()::int64_t *value
    coda_type_get_bit_size()::int64_t *bit_size
    coda_cursor_get_bit_size()::int64_t *bit_size
    coda_cursor_get_byte_size()::int64_t *byte_size
    coda_cursor_get_file_bit_offset()::int64_t *bit_size
    coda_cursor_get_file_byte_offset()::int64_t *byte_size
    coda_recognize_file()::int64_t *file_size
*/
%apply int64_t *OUTPUT { int64_t *dst,
                         int64_t *file_size,
                         int64_t *bit_size,
                         int64_t *byte_size,
                         int64_t *bit_offset,
                         int64_t *byte_offset,
                         int64_t *value };
%apply uint64_t *OUTPUT { uint64_t *dst };


/*
    handle standard integral C type output arguments.
*/
/*
    coda_double_to_datetime()::int *YEAR, int *MONTH, int *DAY, 
                               int *HOUR, int *MINUTE, int *SECOND, int *MUSEC
    coda_get_product_version()::int *version
    coda_type_get_record_field_hidden_status()::int *hidden
    coda_type_get_record_field_available_status()::int *available
    coda_type_get_record_union_status()::int *is_union
    coda_type_get_array_num_dims()::int *num_dims
    coda_type_get_array_dim()::int *num_dims
    coda_cursor_get_depth()::int *depth
    coda_cursor_get_record_field_available_status()::int *available
    coda_recognize_file()::int *product_version
*/
%apply int *OUTPUT { int *YEAR, int *MONTH, int *DAY, 
                     int *HOUR, int *MINUTE, int *SECOND, int *MUSEC,
                     int *version,
                     int *has_ascii_content,
                     int *has_xml_content,
                     int *depth,
                     int *hidden,
                     int *available,
                     int *is_union,
                     int *num_dims,
                     int *product_version };


/*    
    coda_type_get_string_length()::long *length
    coda_cursor_get_string_length()::long *length    
    coda_type_get_num_record_fields()::long *num_fields
    coda_type_get_record_field_index_from_name()::long *index
    coda_cursor_get_index()::long *index
    coda_cursor_get_record_field_index_from_name()::long *index
    coda_cursor_get_available_union_field_index()::long *index
    coda_cursor_get_num_elements()::long *num_elements
*/
%apply long *OUTPUT { long *length,
                      long *num_fields,
                      long *index,
                      long *num_elements };


/*
    handle standard floating point C type output arguments.
*/
%apply float *OUTPUT { float *dst };
/*
    coda_cursor_read_complex_double_split()::double *dst_re, double *dst_im
    coda_datetime_to_double()::double *datetime
    coda_get_time_from_string()::double *time
*/
%apply double *OUTPUT { double *dst,
                        double *dst_re, double *dst_im,
                        double *dst_latitude, double *dst_longitude,
                        double *datetime,
                        double *time };


/*
    handle output "char *" arguments.
    NOTE: this assumes all "char *dst" arguments are output char
    arguments (i.e. not strings).
*/
/*
    coda_cursor_read_char()::char *dst
*/
%apply char *OUTPUT { char *dst };


/*
    handle output "const char **" arguments. This snippet was
    taken from the SWIG files used by the Subversion project.
*/
%apply const char **OUTPUT { const char ** };


/*
    special string handling for user-allocated output strings
*/
/*
    coda_time_to_string()::char *str
*/
%cstring_bounded_output(char *str, 26);


/*
    special string handling for strings allocated by CODA that
    can contain \0 character. the coda library also returns the
    length of the string as a long in this case. however, PyString_
    FromStringAndSize() only supports an int as size parameter.
*/
/*
    coda_type_get_fixed_value()::(const char **fixed_value, long *bit_size)
*/
%apply (const char **BINARY_OUTPUT, long *LENGTH) { (const char **fixed_value, long *length) };


/*
    special string handling for the user-allocated output string
    argument of coda_cursor_read_string().
*/
%typemap(in, numinputs=1) (const coda_Cursor *cursor, char *dst, long dst_size)
{
    SWIG_Python_ConvertPtr($input, (void **)&$1,
                           $1_descriptor,
                           SWIG_POINTER_EXCEPTION | 0);
    if (SWIG_arg_fail($argnum)) SWIG_fail;

    if (coda_cursor_get_string_length($1, &$3) != 0) SWIG_fail;
    $3 = $3 + 1;

    $2 = malloc($3 * sizeof(char));
    if( $2 == NULL )
    {
        return PyErr_NoMemory();
    }
    $2[0] = '\0';
}

%typemap(argout,fragment="t_output_helper") (const coda_Cursor *cursor, char *dst, long dst_size)
{
    $result = t_output_helper($result, PyString_FromString($2));
}

%typemap(freearg) (const coda_Cursor *cursor, char *dst, long dst_size)
{
    free($2);
}


/*
    handle enum output arguments
    NOTE: this assumes all enum TYPENAME * arguments are output arguments!
*/
%apply int *OUTPUT { enum SWIGTYPE * };


/*
    handle output "coda_ProductFile **" argument to coda_open()
*/
%apply opaque_pointer **OUTPUT { coda_ProductFile ** }


/*
    handle output "coda_Type **" arguments to
    coda_get_product_root_type(), coda_type_get_record_field_type(),
    coda_type_get_array_base_type(), coda_type_get_special_base_type(),
    coda_cursor_get_type()
*/
%apply opaque_pointer **OUTPUT { coda_Type ** }


/*
    coda_c_index_to_fortran_index()::(int num_dims, const long dim[])
    coda_cursor_goto_array_element()::(int num_subs, const long subs[])
*/
%apply (int COUNT, const long INPUT_ARRAY[]) { (int num_dims, const long dim[]),
                                              (int num_subs, const long subs[]) };


/*
    coda_type_get_array_dim()::(int *num_dims, long dim[])
    coda_cursor_get_array_dim()::(int *num_dims, long dim[])
*/
%apply (int *COUNT, long OUTPUT_ARRAY[]) { (int *num_dims, long dim[]) };


/*
----------------------------------------------------------------------------------------
- HELPER FUNCTIONS                                                                     -
----------------------------------------------------------------------------------------
*/
/*
    helper functions do not use the global exception mechanism (see below).
    instead, the helper functions flag an exception and return (PyObject *)
    NULL if the return value of underlying coda function is < 0. because the
    return value of the _helper_ function is passed straight to the Python
    interpreter, this will correctly raise the exception in Python.
*/
/*
    make sure PyObject* return values are passed straight back to
    Python.
*/
%apply PyObject *HELPER_FUNCTION_RETURN_VALUE { PyObject* };


/*
    create helper functions for read_*_array functions that read
    simple-type (POSIX/standard C) arrays (e.g. int8_t), standard
    C floating point type (float,double) or characters (read as int8).
*/
NUMARRAY_OUTPUT_HELPER(cursor_read_int8_array,coda_cursor_read_int8_array,int8_t,tInt8)
NUMARRAY_OUTPUT_HELPER(cursor_read_uint8_array,coda_cursor_read_uint8_array,uint8_t,tUInt8)
NUMARRAY_OUTPUT_HELPER(cursor_read_int16_array,coda_cursor_read_int16_array,int16_t,tInt16)
NUMARRAY_OUTPUT_HELPER(cursor_read_uint16_array,coda_cursor_read_uint16_array,uint16_t,tUInt16)
NUMARRAY_OUTPUT_HELPER(cursor_read_int32_array,coda_cursor_read_int32_array,int32_t,tInt32)
NUMARRAY_OUTPUT_HELPER(cursor_read_uint32_array,coda_cursor_read_uint32_array,uint32_t,tUInt32)
NUMARRAY_OUTPUT_HELPER(cursor_read_int64_array,coda_cursor_read_int64_array,int64_t,tInt64)
NUMARRAY_OUTPUT_HELPER(cursor_read_uint64_array,coda_cursor_read_uint64_array,uint64_t,tUInt64)
NUMARRAY_OUTPUT_HELPER(cursor_read_float_array,coda_cursor_read_float_array,float,tFloat32)
NUMARRAY_OUTPUT_HELPER(cursor_read_double_array,coda_cursor_read_double_array,double,tFloat64)
NUMARRAY_OUTPUT_HELPER(cursor_read_char_array,coda_cursor_read_char_array,char,tInt8)


/*
	create helper functions for read_* functions that read
	special type complex as a pair of doubles.
*/
DOUBLE_PAIR_NUMARRAY_OUTPUT_HELPER(cursor_read_complex_double_pair,coda_cursor_read_complex_double_pair)


/*
    create helper functions for read_*_array functions that read
    special type complex into split arrays.
*/
SPLIT_NUMARRAY_OUTPUT_HELPER(cursor_read_complex_double_split_array,coda_cursor_read_complex_double_split_array,double,tFloat64)


/*
	create helper functions to read_*_array functions that read special
	type complex as arrays of pairs of doubles.
*/
DOUBLE_PAIR_ARRAY_NUMARRAY_OUTPUT_HELPER(cursor_read_complex_double_pairs_array,coda_cursor_read_complex_double_pairs_array)


/*
	helper function to read a complex number as a Python object. no associated
	function in the CODA C library exists, i.e. this function is specific to 
	the coda-python module.
*/
%inline
%{
    PyObject * cursor_read_complex(const coda_Cursor *cursor)
    {
        int tmp_result;
        double complex_number[2];

        tmp_result = coda_cursor_read_complex_double_pair(cursor,complex_number);
    
        if (tmp_result < 0)
        {
            return PyErr_Format(codacError,"coda_cursor_read_complex(): %s", coda_errno_to_string(coda_errno));
        }
        
        return PyComplex_FromDoubles(complex_number[0],complex_number[1]);
    }        
%}


/*
    helper function to read an array of complex numbers as a numarray of type
    Complex64. no associated function in the CODA C library exists, i.e. this
    function is specific to the coda-python module.
*/
NUMARRAY_OUTPUT_HELPER(cursor_read_complex_array,coda_cursor_read_complex_double_pairs_array,double,tComplex64)


/*
    typemap to support the helper functions for coda_cursor_read_bits() and
    coda_cursor_read_bytes() (see below).
*/
%typemap(in) int64_t POSIX_SCALAR_INPUT
{
    $1 = (int64_t) PyLong_AsLongLong($input);
}


/*
    coda_cursor_read_bits()::int64_t bit_offset, int64_t bit_length
    coda_cursor_read_bytes()::int64_t offset, int64_t length
*/
%apply int64_t POSIX_SCALAR_INPUT { int64_t bit_offset, int64_t bit_length,
                                    int64_t offset, int64_t length };


/*
    helper function for coda_cursor_read_bits().
*/
%inline
%{
    PyObject *cursor_read_bits(const coda_Cursor *cursor, int64_t bit_offset, int64_t bit_length)
    {
        int64_t byte_length;
        int tmp_byte_length;
        int tmp_result;
        PyArrayObject *tmp;
    
        byte_length = (bit_length >> 3) + ((bit_length & 0x7) != 0 ? 1 : 0);

        /*
            throw an exception if byte_length > INT_MAX, because PyArray_FromDims
            does not support larger array sizes.
        */
        if (byte_length > INT_MAX)
        {
            PyErr_SetString(PyExc_ValueError,"bit_length converted to bytes should not exceed the maximum size of an int.");
            return NULL;
        }
        
        tmp_byte_length = (int)byte_length;
        tmp = (PyArrayObject*)PyArray_FromDims(1, &tmp_byte_length, tUInt8);
        if (tmp == NULL)
        {
            return PyErr_NoMemory();
        }
    
        tmp_result = coda_cursor_read_bits(cursor, (uint8_t *)tmp->data, bit_offset, bit_length);
    
        if (tmp_result < 0)
        {
            Py_DECREF(tmp);
            return PyErr_Format(codacError, "coda_cursor_read_bits(): %s", coda_errno_to_string(coda_errno));
        }
        
        return (PyObject*) tmp;
    }
%}
%ignore coda_cursor_read_bits;


/*
    helper function for coda_cursor_read_bytes().
*/
%inline
%{
    PyObject *cursor_read_bytes(const coda_Cursor *cursor, int64_t offset, int64_t length)
    {
        int tmp_length;
        int tmp_result;
        PyArrayObject *tmp;
    
        /*
            throw an exception if length > INT_MAX, because PyArray_FromDims does not
            support larger array sizes.
        */
        if( length > INT_MAX )
        {
            PyErr_SetString(PyExc_ValueError, "length should not exceed the maximum size of an int.");
            return NULL;
        }
        
        tmp_length = (int)length;
        tmp = (PyArrayObject *)PyArray_FromDims(1, &tmp_length, tUInt8);
        if (tmp == NULL)
        {
            return PyErr_NoMemory();
        }
    
        tmp_result = coda_cursor_read_bytes(cursor, (uint8_t *)tmp->data, offset, length);
    
        if (tmp_result < 0)
        {
            Py_DECREF(tmp);
            return PyErr_Format(codacError, "coda_cursor_read_bytes(): %s", coda_errno_to_string(coda_errno));
        }
        
        return (PyObject*) tmp;
    }
%}
%ignore coda_cursor_read_bytes;


/*
----------------------------------------------------------------------------------------
- GLOBAL EXCEPTION MECHANISM                                                           -
----------------------------------------------------------------------------------------
*/
/*
    first, those declarations to which the exception clause should
    not be attached are declared here and subsequently %ignore'd.
    (i.e. these declarations are ignored when parsing the coda.h
    file; see below). the declarations can be devided into
    two classes:
        - functions that do not return an int (0/-1) flag
        - functions that _do_ return an int, but the return value
          does not represent a (0/-1) error flag.
*/
/*
    functions that do not return an int.
*/
void coda_done(void);
double coda_NaN(void);
double coda_PlusInf(void);
double coda_MinInf(void);
const char *coda_type_get_format_name(coda_format format);
const char *coda_type_get_class_name(coda_type_class type_class);
const char *coda_type_get_native_type_name(coda_native_type native_type);
const char *coda_type_get_special_type_name(coda_special_type special_type);
long coda_c_index_to_fortran_index(int num_dims, const long dim[], long index);
%ignore coda_done;
%ignore coda_NaN;
%ignore coda_PlusInf;
%ignore coda_MinInf;
%ignore coda_type_get_format_name;
%ignore coda_type_get_class_name;
%ignore coda_type_get_native_type_name;
%ignore coda_type_get_special_type_name;
%ignore coda_c_index_to_fortran_index;

/*
    functions that return an int that represents a
    return value instead of an error flag.
*/
int coda_get_option_bypass_special_types(void);
int coda_get_option_perform_boundary_checks(void);
int coda_get_option_perform_conversions(void);
int coda_get_option_use_fast_size_expressions(void);
int coda_get_option_use_mmap(void);
int coda_isNaN(const double x);
int coda_isInf(const double x);
int coda_isPlusInf(const double x);
int coda_isMinInf(const double x);
%ignore coda_get_option_bypass_special_types;
%ignore coda_get_option_perform_boundary_checks;
%ignore coda_get_option_perform_conversions;
%ignore coda_get_option_use_fast_size_expressions;
%ignore coda_get_option_use_mmap;
%ignore coda_isNaN;
%ignore coda_isInf;
%ignore coda_isPlusInf;
%ignore coda_isMinInf;


/*
    default exception clause for CODA errors. this will raise
    a codac.CodacError exception in Python.
*/
%exception
{
    $action
    
    if (result < 0)
    {
        $cleanup
        return PyErr_Format(codacError,"$name(): %s", coda_errno_to_string(coda_errno));
    }
}
/*
    replace typemap for int return values with the typemap
    for void return values.
*/
%typemap(out) int;
%typemap(out) int = void;


/*
----------------------------------------------------------------------------------------
- MAIN HEADER FILE INCLUDE (coda.h)                                                    -
----------------------------------------------------------------------------------------
*/
/*
    wrap everything in coda.h
*/
%include "coda.h"
