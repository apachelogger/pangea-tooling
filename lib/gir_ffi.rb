# frozen_string_literal: true
#
# Copyright (C) 2018-2021 Harald Sitter <sitter@kde.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) version 3, or any
# later version accepted by the membership of KDE e.V. (or its
# successor approved by the membership of KDE e.V.), which shall
# act as a proxy defined in Section 6 of version 3 of the license.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

# https://github.com/mvz/gir_ffi/issues/91
module GLibLoadClassWorkaround
  def load_class(klass, *args)
    return if klass == :IConv

    super
  end
end

# Prepended with workaround
module GirFFI
  # Prepended with workaround
  module ModuleBase
    prepend GLibLoadClassWorkaround
  end
end

# TODO: verify if this is still necessary from time to time
# Somewhere in test-unit the lib path is injected in the load paths and since
# the file has the same name as the original require this would cause
# a recursion require. So, rip the current path out of the load path temorarily.
old_paths = $LOAD_PATH.dup
$LOAD_PATH.reject! { |x| x == __dir__ }
require 'gir_ffi'
$LOAD_PATH.replace(old_paths)
